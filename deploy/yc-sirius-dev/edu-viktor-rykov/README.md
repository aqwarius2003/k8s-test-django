# Развертывание Django Site в Kubernetes (yc-sirius-dev)

Пошаговая инструкция по развертыванию Django приложения в Kubernetes кластере Яндекс Облака.

## Окружение

- **Кластер:** yc-sirius-dev
- **Namespace:** edu-viktor-rykov
- **Домен:** edu-viktor-rykov.yc-sirius-dev.pelid.team
- **Docker Hub:** aqwarius2003/django-site

## Предварительные требования

Перед началом убедитесь, что у вас есть:

1. **Доступ к кластеру Kubernetes**
   - Настроенный `kubectl` с доступом к кластеру
   - Права на создание ресурсов в namespace `edu-viktor-rykov`

2. **Docker и Docker Hub**
   - Установленный Docker Desktop
   - Аккаунт на Docker Hub
   - Авторизация: `docker login`

3. **Доступ к PostgreSQL**
   - Managed PostgreSQL в Яндекс Облаке
   - Строка подключения (DSN)
   - SSL-сертификат для подключения

4. **Git репозиторий**
   - Клонированный репозиторий проекта
   - Рабочая директория: `D:\Python_projects\k8s-test-django`

## Проверка доступа к кластеру

```powershell
# Проверьте подключение к кластеру
kubectl cluster-info

# Проверьте текущий namespace
kubectl config view --minify | Select-String namespace

# Посмотрите существующие ресурсы
kubectl get all
```

## Шаг 1: Подготовка SSL-сертификата PostgreSQL

### 1.1. Скачайте SSL-сертификат Yandex Cloud

```powershell
# Создайте папку для сертификатов (если еще не создана)
New-Item -ItemType Directory -Path "deploy\yc-sirius-dev\edu-viktor-rykov\certs" -Force

# Скачайте сертификат
Invoke-WebRequest -Uri "https://storage.yandexcloud.net/cloud-certs/CA.pem" -OutFile "deploy\yc-sirius-dev\edu-viktor-rykov\certs\root.crt"
```

### 1.2. Создайте Secret с SSL-сертификатом

```powershell
# Создайте Secret (если еще не создан)
kubectl create secret generic postgresql-ssl-cert --from-file=root.crt=deploy\yc-sirius-dev\edu-viktor-rykov\certs\root.crt

# Проверьте создание
kubectl get secret postgresql-ssl-cert
```

## Шаг 2: Настройка переменных окружения

### 2.1. Получите данные для подключения к PostgreSQL

```powershell
# Посмотрите секрет postgres (содержит DSN для подключения)
kubectl get secret postgres -o yaml

# Декодируйте DSN
kubectl get secret postgres -o jsonpath="{.data.dsn}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

### 2.2. Создайте ConfigMap для Django

Отредактируйте файл `manifests/django-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: django-config
  namespace: edu-viktor-rykov
data:
  ALLOWED_HOSTS: "*"
  DEBUG: "False"
  DATABASE_URL: "postgres://USER:PASSWORD@HOST:PORT/DATABASE?sslmode=verify-full"
```

**Важно:** Замените `DATABASE_URL` на реальную строку подключения из секрета `postgres`.

Примените ConfigMap:

```powershell
kubectl apply -f deploy\yc-sirius-dev\edu-viktor-rykov\manifests\django-configmap.yaml
```

### 2.3. Создайте Secret для Django

Сгенерируйте SECRET_KEY:

```powershell
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

Создайте Secret (замените `<your-secret-key>` на сгенерированный ключ):

```powershell
kubectl create secret generic django-secret --from-literal=SECRET_KEY='<your-secret-key>'

# Проверьте создание
kubectl get secret django-secret
```

## Шаг 3: Сборка и публикация Docker образа

### 3.1. Соберите и загрузите образ в Docker Hub

```powershell
# Перейдите в корень проекта
cd D:\Python_projects\k8s-test-django

# Запустите скрипт сборки (автоматически)
.\build-and-push.ps1

# Скрипт выполнит:
# - Получит хэш текущего коммита
# - Соберет Docker образ
# - Создаст теги с хэшем и latest
# - Загрузит образы в Docker Hub
```

### 3.2. Проверьте образ на Docker Hub

Откройте в браузере: https://hub.docker.com/r/aqwarius2003/django-site/tags

Убедитесь, что образ загружен с правильным тегом.

## Шаг 4: Развертывание Django в кластере

### 4.1. Примените Deployment

```powershell
kubectl apply -f deploy\yc-sirius-dev\edu-viktor-rykov\manifests\django-deployment.yaml
```

### 4.2. Проверьте статус Deployment

```powershell
# Проверьте Deployment
kubectl get deployments

# Проверьте Pods
kubectl get pods -l app=django

# Посмотрите логи
kubectl logs -l app=django --tail=50

# Если под не запускается, посмотрите детали
kubectl describe pod -l app=django
```

### 4.3. Создайте Service

```powershell
kubectl apply -f deploy\yc-sirius-dev\edu-viktor-rykov\manifests\django-service.yaml

# Проверьте Service
kubectl get svc django-service

# Проверьте endpoints
kubectl get endpoints django-service
```

## Шаг 5: Выполнение миграций и создание суперпользователя

### 5.1. Выполните миграции Django

```powershell
# Получите имя пода
kubectl get pods -l app=django

# Выполните миграции (замените <pod-name> на реальное имя)
kubectl exec -it <pod-name> -- python manage.py migrate

# Или используйте автоматический поиск пода:
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- python manage.py migrate
```

### 5.2. Создайте суперпользователя

```powershell
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- python manage.py createsuperuser

# Введите:
# - Username
# - Email (можно оставить пустым)
# - Password (дважды)
```

## Шаг 6: Настройка Nginx для проксирования

### 6.1. Примените ConfigMap для Nginx

```powershell
kubectl apply -f deploy\yc-sirius-dev\edu-viktor-rykov\manifests\main-nginx-configmap.yaml
```

### 6.2. Перезапустите Nginx

```powershell
# Перезапустите Deployment
kubectl rollout restart deployment main-nginx

# Дождитесь завершения
kubectl rollout status deployment main-nginx

# Проверьте статус
kubectl get pods -l app=main-nginx
```

## Шаг 7: Проверка работы приложения

### 7.1. Проверьте доступность сайта

Откройте в браузере: **https://edu-viktor-rykov.yc-sirius-dev.pelid.team**

Должна открыться главная страница Django.

### 7.2. Проверьте админку

Откройте: **https://edu-viktor-rykov.yc-sirius-dev.pelid.team/admin/**

Войдите под созданным суперпользователем.

### 7.3. Проверьте логи

```powershell
# Логи Django
kubectl logs -l app=django --tail=50

# Логи Nginx
kubectl logs -l app=main-nginx --tail=50

# События в namespace
kubectl get events --sort-by='.lastTimestamp'
```

## Обновление приложения

### Выкатка новой версии

```powershell
# 1. Внесите изменения в код
# 2. Сделайте коммит
git add .
git commit -m "Описание изменений"

# 3. Соберите и загрузите новый образ
.\build-and-push.ps1

# 4. Перезапустите Deployment (если используете тег latest)
kubectl rollout restart deployment django-app

# 5. Дождитесь завершения
kubectl rollout status deployment django-app

# 6. Примените миграции (если есть новые)
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- python manage.py migrate

# 7. Проверьте работу сайта
```

### Откат на предыдущую версию

```powershell
# Посмотрите историю
kubectl rollout history deployment django-app

# Откатитесь
kubectl rollout undo deployment django-app
```

## Диагностика проблем

### Под не запускается (CrashLoopBackOff)

```powershell
# Посмотрите логи
kubectl logs -l app=django --tail=100

# Посмотрите описание пода
kubectl describe pod -l app=django

# Проверьте образ
kubectl get deployment django-app -o jsonpath='{.spec.template.spec.containers[0].image}'

# Проверьте переменные окружения
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- env
```

### Ошибка подключения к БД

```powershell
# Проверьте SSL-сертификат в контейнере
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- ls -la /root/.postgresql/

# Проверьте права на файл (должны быть 0600)
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- stat /root/.postgresql/root.crt

# Проверьте DATABASE_URL
kubectl get configmap django-config -o yaml

# Попробуйте подключиться к БД вручную
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- python manage.py dbshell
```

### Сайт недоступен (502 Bad Gateway)

```powershell
# Проверьте, что Django работает
kubectl get pods -l app=django

# Проверьте Service и endpoints
kubectl get svc django-service
kubectl get endpoints django-service

# Проверьте ConfigMap Nginx
kubectl get configmap main-nginx-config -o yaml

# Проверьте логи Nginx
kubectl logs -l app=main-nginx --tail=50

# Проверьте, может ли Nginx достучаться до Django
kubectl exec -it (kubectl get pods -l app=main-nginx -o jsonpath='{.items[0].metadata.name}') -- curl -I django-service:80
```

## Полезные команды

```powershell
# Посмотреть все ресурсы
kubectl get all

# Следить за подами
kubectl get pods -w

# Подключиться к shell контейнера
kubectl exec -it (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}') -- /bin/bash

# Скопировать файл из пода
kubectl cp (kubectl get pods -l app=django -o jsonpath='{.items[0].metadata.name}'):/path/to/file ./local-file

# Масштабирование
kubectl scale deployment django-app --replicas=3

# Удалить все ресурсы (осторожно!)
kubectl delete deployment django-app
kubectl delete service django-service
kubectl delete configmap django-config
kubectl delete secret django-secret
```

## Структура файлов

```
deploy/yc-sirius-dev/edu-viktor-rykov/
├── README.md                      # Эта инструкция
├── certs/
│   └── root.crt                   # SSL-сертификат PostgreSQL
├── manifests/
│   ├── django-configmap.yaml      # Переменные окружения Django
│   ├── django-deployment.yaml     # Deployment для Django
│   ├── django-service.yaml        # Service для Django
│   └── main-nginx-configmap.yaml  # Конфигурация Nginx
└── scripts/
    └── build-and-push.sh          # Скрипт сборки для Linux/macOS
```
