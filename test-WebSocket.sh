#!/bin/bash

textcolor='\033[0;36m'
textcolor_light='\033[1;36m'
red='\033[1;31m'
green='\033[0;32m'
clear='\033[0m'

# Прекратить выполнение при ошибке
set -e

# Функция установки
install() {
  # Обновление пакетов
  # sudo apt update
  # sudo apt upgrade -y

  # Установка необходимых пакетов
  sudo apt install -y curl wget uuid-runtime

  # Генерация UUID для пользователя Sing-box
  UUID=$(uuidgen)

  # Получение IP-адреса сервера
  SERVER_IP=$(hostname -I | awk '{print $1}')

  # Запрос домена у пользователя
  read -p "Пожалуйста, введите ваше доменное имя (например, example.com): " DOMAIN_NAME

  # Установка Caddy
  echo ""
  echo ""
  echo -e "${green}Установка Caddy...${clear}"
  echo ""
  echo ""
  echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" | sudo tee /etc/apt/sources.list.d/caddy-fury.list
  sudo apt update
  sudo apt install -y caddy

  # Установка Sing-box
  echo ""
  echo ""
  echo -e "${green}Установка Sing-box...${clear}"
  echo ""
  echo ""
  SING_BOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep 'tag_name' | cut -d\" -f4)
  SING_BOX_VERSION=${SING_BOX_VERSION#v} # Удаление 'v' в начале, если есть
  wget https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64.tar.gz -O sing-box.tar.gz
  tar -xzf sing-box.tar.gz
  sudo mv sing-box-${SING_BOX_VERSION}-linux-amd64/sing-box /usr/local/bin/
  sudo chmod +x /usr/local/bin/sing-box
  rm -rf sing-box-${SING_BOX_VERSION}-linux-amd64 sing-box.tar.gz

  # Создание директории для конфигурации Sing-box
  sudo mkdir -p /etc/sing-box

  # Создание файла конфигурации Sing-box
  echo ""
  echo ""
  echo -e "${green}Создание конфигурации Sing-box...${clear}"
  echo ""
  echo ""
  sudo tee /etc/sing-box/config.json >/dev/null <<EOF
{  
  // Какие логи хотим видеть
  "log": {
    "disabled": false,
    "timestamp": true,
    "level": "error",
    "output": "singbox.log"
  },
  // DNS сервера
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "tls://1.1.1.1"
      },
      {
        "tag": "dns-block",
        "address": "rcode://success"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "category-ads-all"
        ],
        "server": "dns-block",
        "disable_cache": true
      },
      {
        "outbound": "any",
        "server": "dns-remote"
      }
    ],
    "final": "dns-remote",
    "disable_cache": false,
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": 50051,
      "sniff": true,
      "domain_strategy": "ipv4_only",
      "users": [
        {
          "name": "test",
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/ws"
      }
    }
  ],
  "outbounds": [
    // Прямое подключение
    {
      "type": "direct",
      "tag": "direct-out"
    },
    // Блокируем соединение
    {
      "type": "block",
      "tag": "block-out"
    },
    // DNS ответы
    {
      "type": "dns",
      "tag": "dns-out"
    },
  ],
  "route": {
    // Список правил с базами GEOIP или GEOSITES
    "rule_set": [
      // Получаем список ВСЕЙ рекламы
      {
        "type": "remote",
        "tag": "category-ads-all",
        "format": "binary",
        "url": "https://github.com/lyc8503/sing-box-rules/raw/refs/heads/rule-set-geosite/geosite-category-ads-all.srs",
      }
    ],
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "rule_set": [
          "category-ads-all"
        ],
        "outbound": "block-out"
      },
      {
        "protocol": "quic",
        "outbound": "block-out"
      },
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF
  # Создание Caddyfile
  echo "Настройка Caddy..."
  sudo tee /etc/caddy/Caddyfile >/dev/null <<EOF
# Добавляем логгирование
{
    log {
        level DEBUG
        output file /var/log/caddy/access.log {
            roll true
            roll_size 5mb
            roll_keep 2
            roll_keep_for 48h
        }
    }
}

${DOMAIN_NAME} {
    encode gzip

    @websocket {
        path /ws
    }

    reverse_proxy @websocket localhost:50051 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }

    # Обслуживание остальных запросов
    handle_path / {
        respond "Welcome to ${DOMAIN_NAME}"
    }
}
EOF

  # Перезагрузка Caddy для применения конфигурации
  sudo systemctl reload caddy

  # Создание системной службы для Sing-box
  echo ""
  echo ""
  echo -e "${green}Настройка Sing-box как системной службы...${clear}"
  echo ""
  echo ""
  sudo tee /etc/systemd/system/sing-box.service >/dev/null <<EOF
[Unit]
Description=Sing-box Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Перезагрузка systemd и запуск Sing-box
  sudo systemctl daemon-reload
  sudo systemctl enable sing-box
  sudo systemctl start sing-box

  # Вывод информации о конфигурации
  echo "Установка завершена!"
  echo "----------------------------------------"
  echo "Ваш VLESS-прокси с Sing-box настроен."
  echo "Доменное имя: ${DOMAIN_NAME}"
  echo "IP сервера: ${SERVER_IP}"
  echo "UUID: ${UUID}"
  echo "----------------------------------------"
  echo "Убедитесь, что A-запись вашего домена указывает на IP вашего сервера."
  echo "Теперь вы можете настроить ваш VLESS-клиент с использованием этой информации."
}

# Функция удаления
uninstall() {
  echo ""
  echo ""
  echo -e "${red}Удаление Sing-box и Caddy...${clear}"
  echo ""
  echo ""
  # Остановка и отключение служб
  sudo systemctl stop sing-box || true
  sudo systemctl disable sing-box || true
  sudo systemctl stop caddy || true
  sudo systemctl disable caddy || true

  # Удаление файлов и директорий
  sudo rm -rf /usr/local/bin/sing-box
  sudo rm -rf /etc/sing-box
  sudo rm -rf /etc/systemd/system/sing-box.service
  sudo rm -rf /etc/caddy
  sudo rm -rf /etc/apt/sources.list.d/caddy-fury.list
  sudo rm -rf /var/log/caddy/access.log

  # Удаление пакетов
  sudo apt purge -y caddy

  # Перезагрузка systemd
  sudo systemctl daemon-reload

  # Автоудаление ненужных пакетов
  sudo apt autoremove -y
  echo ""
  echo ""
  echo -e "${green}Удаление завершено!${clear}"
  echo ""
  echo ""
}

# Проверка параметров командной строки
if [[ "$1" == "--uninstall" ]]; then
  uninstall
else
  install
fi
