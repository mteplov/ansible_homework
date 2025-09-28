#!/bin/bash
# ========================================================
# Автоскрипт Ansible: Задания 1-3 с проверками и GitHub
# Исправлено: motd без encoding, UTF-8 index.html
# ========================================================

BASE_DIR=~/ansible_homework
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# -----------------------
# Inventory
# -----------------------
cat > inventory.ini << 'EOF'
[localhost]
localhost ansible_connection=local
EOF

# -----------------------
# Плейбуки
# -----------------------

# --- Задание 1: Скачивание и распаковка Kafka ---
cat > download_unpack.yml << 'EOF'
---
- name: Task 1:Downloading and unpacking Kafka
  hosts: localhost
  become: yes
  vars:
    kafka_url: "https://downloads.apache.org/kafka/3.8.1/kafka_2.13-3.8.1.tgz"
    kafka_dest: "/opt/kafka"
    kafka_tmp: "/tmp/kafka.tgz"
  tasks:
    - name: Удаляем старую папку Kafka
      file:
        path: "{{ kafka_dest }}"
        state: absent
      ignore_errors: yes

    - name: Создаем папку назначения
      file:
        path: "{{ kafka_dest }}"
        state: directory
        mode: '0755'

    - name: Скачиваем Kafka
      get_url:
        url: "{{ kafka_url }}"
        dest: "{{ kafka_tmp }}"
        mode: '0644'

    - name: Распаковываем Kafka
      unarchive:
        src: "{{ kafka_tmp }}"
        dest: "{{ kafka_dest }}"
        remote_src: yes
        extra_opts: [--strip-components=1]
EOF

# --- Задание 1: Установка Tuned ---
cat > install_tuned.yml << 'EOF'
---
- name: Установка и запуск Tuned
  hosts: localhost
  become: yes
  tasks:
    - name: Устанавливаем Tuned
      apt:
        name: tuned
        state: present
        update_cache: yes

    - name: Запускаем Tuned и включаем автозапуск
      systemd:
        name: tuned
        state: started
        enabled: yes
EOF

# --- Задание 1: Изменение приветствия ---
cat > change_motd.yml << 'EOF'
---
- name: Изменение приветствия системы
  hosts: localhost
  become: yes
  vars:
    motd_text: "Добро пожаловать на систему Ansible!"
  tasks:
    - name: Устанавливаем motd
      copy:
        content: "{{ motd_text }}"
        dest: /etc/motd
        owner: root
        group: root
        mode: '0644'
EOF

# --- Задание 2: Приветствие с IP и hostname ---
cat > change_motd_ip.yml << 'EOF'
---
- name: Изменение motd с IP и hostname
  hosts: localhost
  become: yes
  tasks:
    - name: Собираем IP и hostname
      set_fact:
        motd_text: |
          Хост: {{ ansible_hostname }}
          IP: {{ ansible_default_ipv4.address }}
          Хорошего дня, системный администратор! 

    - name: Устанавливаем motd
      copy:
        content: "{{ motd_text }}"
        dest: /etc/motd
        owner: root
        group: root
        mode: '0644'
EOF

# --- Задание 3: Роль Apache ---
mkdir -p roles/apache_info/tasks roles/apache_info/templates roles/apache_info/handlers

# Роль tasks/main.yml
cat > roles/apache_info/tasks/main.yml << 'EOF'
---
- name: Установка Apache
  apt:
    name: apache2
    state: present
    update_cache: yes
  become: yes

- name: Определяем первый диск
  set_fact:
    first_disk: "{{ ansible_devices.keys() | list | first }}"

- name: Создаем index.html с фактами системы
  template:
    src: index.html.j2
    dest: /var/www/html/index.html
  notify: restart apache

- name: Запускаем Apache и включаем автозапуск
  systemd:
    name: apache2
    state: started
    enabled: yes
  become: yes

- name: Проверка доступности веб-сайта
  uri:
    url: http://localhost
    status_code: 200
EOF

# Роль templates/index.html.j2
cat > roles/apache_info/templates/index.html.j2 << 'EOF'
<html>
<head>
<meta charset="UTF-8">
<title>System Info</title>
</head>
<body>
<h1>Характеристики хоста {{ ansible_hostname }}</h1>
<ul>
  <li>CPU cores: {{ ansible_processor_cores | default(ansible_processor_vcpus, 'unknown') }}</li>
  <li>RAM: {{ ansible_memtotal_mb }} MB</li>
  {% set first_disk = ansible_devices.keys() | list | first %}
  <li>Первый HDD: {{ ansible_devices[first_disk]['size'] }}</li>
  <li>IP: {{ ansible_default_ipv4.address }}</li>
</ul>
</body>
</html>
EOF

# Роль handlers/main.yml
cat > roles/apache_info/handlers/main.yml << 'EOF'
---
- name: restart apache
  systemd:
    name: apache2
    state: restarted
EOF

# site.yml
cat > site.yml << 'EOF'
---
- name: Установка и проверка Apache
  hosts: localhost
  become: yes
  roles:
    - apache_info
EOF

# -----------------------
# Проверка и установка пакетов
# -----------------------
check_and_install() {
    PACKAGE=$1
    DESC=$2
    if ! dpkg -s "$PACKAGE" &> /dev/null; then
        read -p "$DESC не установлен. Установить? (да/нет): " ANSWER
        if [[ "$ANSWER" == "да" || "$ANSWER" == "y" ]]; then
            echo "Введите пароль sudo для установки $PACKAGE"
            sudo apt update
            sudo apt install -y "$PACKAGE"
        fi
    fi
}

check_and_install "ansible" "Ansible"
check_and_install "apache2" "Apache"
check_and_install "tuned" "Tuned"

# -----------------------
# Функция запуска плейбука
# -----------------------
run_playbook() {
    PLAYBOOK=$1
    DESC=$2
    echo
    echo "=== 🚀 Запуск: $DESC ==="
    ANSIBLE_BECOME_PROMPT="Введите пароль sudo: " \
        ansible-playbook -i inventory.ini "$PLAYBOOK" --become --ask-become-pass

    echo "=== 🔍 Статус после $DESC ==="
    case "$PLAYBOOK" in
        download_unpack.yml)
            if [ -d /opt/kafka ]; then
                echo -e "✅ Kafka распакован в /opt/kafka\n"
                ls -lh /opt/kafka | head -10
            else
                echo -e "❌ Kafka отсутствует!\n"
            fi
            ;;
        install_tuned.yml)
            echo -e "=== Tuned service status ===\n"
            systemctl status tuned --no-pager -n 10
            ;;
        change_motd.yml|change_motd_ip.yml)
            echo -e "\nТекущее приветствие:\n$(cat /etc/motd)\n"
            ;;
        site.yml)
            echo -e "\n=== Apache service status ===\n"
            systemctl status apache2 --no-pager -n 10
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
            echo -e "\nHTTP код сайта: $HTTP_CODE\n"
            ;;
    esac
    echo -e "=== ✅ Завершено: $DESC ===\n"
    read -p "Нажмите Enter для продолжения..."
}

# -----------------------
# Запуск плейбуков
# -----------------------
run_playbook download_unpack.yml "Скачивание и распаковка Kafka"
run_playbook install_tuned.yml "Установка и запуск Tuned"
run_playbook change_motd.yml "Изменение приветствия системы"
run_playbook change_motd_ip.yml "Изменение приветствия с IP и hostname"
run_playbook site.yml "Установка и проверка Apache с index.html"

# -----------------------
# Версии компонентов
# -----------------------
echo -e "\n=== Сводка версий ==="
echo "Ansible: $(ansible --version | head -n1)"
echo "Apache: $(apache2 -v | head -1)"
echo "Tuned: $(tuned-adm active)"
if [ -d /opt/kafka ]; then
    echo "Kafka: $(ls /opt/kafka | head -1)"
fi

# -----------------------
# GitHub push
# -----------------------
read -p "Выгружать проект на GitHub? (да/нет): " PUSH
if [[ "$PUSH" == "да" || "$PUSH" == "y" ]]; then
    read -p "Введите ваш GitHub логин: " GH_USER
    if [ ! -d .git ]; then
        git init
        git remote add origin git@github.com:$GH_USER/ansible_homework.git
    fi

    # Проверяем текущую ветку
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

    # Если ветки нет, создаём main
    if [ "$CURRENT_BRANCH" != "main" ]; then
        git branch -M main
        CURRENT_BRANCH="main"
    fi

    git add .
    git commit -m "Обновление плейбуков и роли: $(date +"%Y-%m-%d %H:%M:%S")" || echo "Нет изменений для коммита"
    git push -u origin "$CURRENT_BRANCH"
    echo "✅ Проект выгружен на GitHub (ветка $CURRENT_BRANCH)"
else
    echo "Проект не выгружен. Скрипт завершил выполнение."
fi


