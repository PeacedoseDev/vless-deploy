#!/bin/bash

# Прекратить выполнение при ошибке
set -e

# Функция установки
install() {
    # Обновление пакетов
    sudo apt update
    sudo apt upgrade -y

    # Установка необходимых пакетов
    sudo apt install -y curl wget unzip uuid-runtime

    # Генерация UUID для пользователя Sing-box
    UUID=$(uuidgen)

    # Получение IP-адреса сервера
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Запрос домена у пользователя
    read -p "Пожалуйста, введите ваше доменное имя (например, example.com): " DOMAIN_NAME

    # Установка Caddy
    echo "Установка Caddy..."
    echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" | sudo tee /etc/apt/sources.list.d/caddy-fury.list
    sudo apt update
    sudo apt install -y caddy

    # Установка Sing-box
    echo "Установка Sing-box..."
    SING_BOX_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep 'tag_name' | cut -d\" -f4)
    SING_BOX_VERSION=${SING_BOX_VERSION#v} # Удаление ведущего 'v', если есть
    wget https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-amd64.zip -O sing-box.zip
    unzip sing-box.zip -d sing-box
    sudo mv sing-box/sing-box /usr/local/bin/
    sudo chmod +x /usr/local/bin/sing-box
    rm -rf sing-box sing-box.zip

    # Создание директории для конфигурации Sing-box
    sudo mkdir -p /etc/sing-box

    # Создание файла конфигурации Sing-box
    echo "Создание конфигурации Sing-box..."
    sudo tee /etc/sing-box/config.json > /dev/null <<EOF
{
  "log": {
    "level": "info",
    "output": "console"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": 50051,
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "grpc"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # Создание Caddyfile
    echo "Настройка Caddy..."
    sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
${DOMAIN_NAME}

encode gzip

@grpc {
    path /grpc
    protocol h2c
}

reverse_proxy @grpc localhost:50051
EOF

    # Перезагрузка Caddy для применения конфигурации
    sudo systemctl reload caddy

    # Создание системной службы для Sing-box
    echo "Настройка Sing-box как системной службы..."
    sudo tee /etc/systemd/system/sing-box.service > /dev/null <<EOF
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
    echo "Удаление Sing-box и Caddy..."

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

    # Удаление пакетов
    sudo apt purge -y caddy

    # Перезагрузка systemd
    sudo systemctl daemon-reload

    # Автоудаление ненужных пакетов
    sudo apt autoremove -y

    echo "Удаление завершено!"
}

# Проверка параметров командной строки
if [[ "$1" == "--uninstall" ]]; then
    uninstall
else
    install
fi
