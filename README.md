# Django Site

Докеризированный сайт на Django для экспериментов с Kubernetes.

Внутри контейнера Django приложение запускается с помощью **Nginx Unit**, не путать с **Nginx**. Сервер **Nginx Unit** выполняет сразу две функции: как веб-сервер он раздаёт файлы статики и медиа, а в роли сервера-приложений он запускает Python и Django. Таким образом, **Nginx Unit** заменяет собой связку из двух сервисов **Nginx** и **Gunicorn/uWSGI**. [Подробнее про Nginx Unit](https://unit.nginx.org/).

## Как подготовить окружение к локальной разработке

Код в репозитории полностью докеризирован, поэтому для запуска приложения вам понадобится **Docker**. Инструкции по его установке ищите на официальных сайтах:

- [Get Started with Docker](https://www.docker.com/get-started/)

Вместе со свежей версией Docker к вам на компьютер автоматически будет установлен **Docker Compose**. Дальнейшие инструкции будут его активно использовать.

## Как запустить сайт для локальной разработки

Запустите базу данных и сайт:

```bash
$ docker compose up
```

В новом терминале, не выключая сайт, запустите несколько команд:

```bash
$ docker compose run --rm web ./manage.py migrate  # создаём/обновляем таблицы в БД
$ docker compose run --rm web ./manage.py createsuperuser  # создаём в БД учётку суперпользователя
```

Готово. Сайт будет доступен по адресу [http://127.0.0.1:8080](http://127.0.0.1:8080). Вход в админку находится по адресу [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/).

## Как вести разработку

Все файлы с кодом Django смонтированы внутрь докер-контейнера, чтобы Nginx Unit сразу видел изменения в коде и не требовал постоянно пересборки докер-образа. Для этого достаточно перезапустить сервисы **Docker Compose**.

### Как обновить приложение из основного репозитория

Чтобы обновить приложение до последней версии, подтяните код из центрального окружения и пересоберите докер-образы:

```bash
$ git pull
$ docker compose build
```

После обновления кода из репозитория стоит также обновить и схему БД. Вместе с коммитом могли прилететь новые миграции схемы БД, и без них код не запустится.

Чтобы не гадать, заведётся ли код или нет — запускайте при каждом обновлении команду **migrate**. Если найдутся свежие миграции, то команда их применит:

```bash
$ docker compose run --rm web ./manage.py migrate
# Running migrations:
#   No migrations to apply.
```

### Как добавить библиотеку в зависимости

В качестве менеджера пакетов для образа с Django используется **pip** с файлом **requirements.txt**. Для установки новой библиотеки достаточно прописать её в файл **requirements.txt** и запустить сборку докер-образа:

```bash
$ docker compose build web
```

Аналогичным образом можно удалять библиотеки из зависимостей.

## Развертывание в Kubernetes (Minikube)

Приложение полностью готово к развертыванию в Kubernetes. Для локального тестирования используется **Minikube**.

### Предварительные требования

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Docker (уже установлен для локальной разработки)

### Подготовка Docker образа

Сначала соберите Docker образ для Minikube:

```bash
# Настройте Docker для работы с Minikube
eval $(minikube docker-env)

# Проверить, что переключились:
docker ps  # должно показывать контейнеры в Minikube

# Проверить куда указывает Docker
docker info | grep -i "name\|server"

# Соберите образ
cd backend_main_django
docker build -t django_app:latest .
cd ..
```

### Запуск базы данных

Отвяжите Docker от Minikube:

```bash
# Отменить переменные окружения Minikube
eval $(minikube docker-env -u)

# Проверить
docker ps  # теперь покажет контейнеры на хосте

# Запустите только БД из docker-compose
docker-compose up -d db
```

### Развертывание приложения в Kubernetes

#### Шаг 1: Создание Secret для конфиденциальных данных

```bash
# Получите ваш IP адрес
export HOST_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
echo "Используем IP адрес: $HOST_IP"

# Создайте Secret с конфиденциальными данными
kubectl create secret generic django-secret \
  --from-literal=SECRET_KEY=your-production-secret-key-here \
  --from-literal=DATABASE_URL=postgres://test_k8s:OwOtBep9Frut@$HOST_IP:5432/test_k8s
```

#### Шаг 2: Применение манифеста Deployment

```bash
# Примените манифест с использованием Secret
kubectl apply -f kubernetes/django-deployment-with-secrets.yaml

# Проверьте статус подов
kubectl get pods

# Дождитесь запуска подов
kubectl wait --for=condition=Ready pod -l app=django-app --timeout=300s
```

#### Шаг 3: Выполнение миграций

```bash
# Выполните миграции в одном из подов
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py migrate

# Создайте суперпользователя (опционально)
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py createsuperuser
```

#### Шаг 4: Создание сервиса для доступа

```bash
# Создайте сервис для доступа к приложению
kubectl expose deployment django-app-deployment --type=NodePort --port=80

# Получите URL для доступа
minikube service django-app-deployment --url
```

### Проверка работы

```bash
# Проверьте подключение к БД
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py shell -c 'from django.db import connection; connection.ensure_connection(); print("Database connection successful")'

# Посмотрите логи приложения
kubectl logs -l app=django-app --tail=50

# Откройте Minikube Dashboard
minikube dashboard
```

### Структура манифестов

Все манифесты Kubernetes находятся в директории `kubernetes/`:

- `django-deployment-with-secrets.yaml` - Deployment с использованием Secret для конфиденциальных данных
- `django-pod.yaml` - Pod манифест для тестирования

### Важные замечания

1. **Secret содержит конфиденциальные данные** — не коммитьте Secret в репозиторий. Создавайте его вручную в каждом окружении.
2. **DATABASE_URL должен содержать реальный IP адрес** — замените `$HOST_IP` на ваш реальный IP адрес хост-машины.
3. **Манифесты не содержат секретных значений** — все конфиденциальные данные хранятся в Secret и подставляются через `valueFrom.secretKeyRef`.
4. **Для очистки всех ресурсов** используйте:
   ```bash
   kubectl delete all --all
   ```

### Настройка Ingress для удобного доступа

Вместо использования **NodePort** с динамическими портами, можно настроить **Ingress** для доступа по доменному имени.

#### Включение Ingress addon

```bash
# Включите Ingress addon в Minikube
minikube addons enable ingress

# Дождитесь запуска Ingress контроллера
kubectl get pods -n ingress-nginx
```

Примените манифесты:

```bash
kubectl apply -f kubernetes/django-service.yaml
kubectl apply -f kubernetes/django-ingress.yaml

# Проверьте Ingress
kubectl get ingress
```

#### Настройка доступа по доменному имени

```bash
# Добавьте запись в /etc/hosts
echo "$(minikube ip) django-app.local" | sudo tee -a /etc/hosts

# Откройте в браузере: http://django-app.local
```

**Преимущества Ingress:**

- Удобный доступ по доменному имени вместо IP:порт.
- Возможность настройки HTTPS.
- Балансировка нагрузки между подами.
- Более гибкая маршрутизация.

## Автоматическая очистка сессий с помощью CronJob

Django накапливает устаревшие сессии в базе данных. Для их автоматической очистки используется **CronJob**.

### Проверка и очистка сессий вручную

```bash
# Проверьте количество сессий в БД
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py shell -c "from django.contrib.sessions.models import Session; print(f'Sessions count: {Session.objects.count()}')"

# Выполните очистку устаревших сессий
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py clearsessions

# Проверьте результат
kubectl exec -it $(kubectl get pods -l app=django-app -o jsonpath='{.items[0].metadata.name}') -- python manage.py shell -c "from django.contrib.sessions.models import Session; print(f'Sessions count after cleanup: {Session.objects.count()}')"
```

#### Автоматическая очистка через CronJob

Для автоматической очистки сессий по расписанию используется **CronJob** манифест `kubernetes/clearsessions-cronjob.yaml`:

```bash
# Примените CronJob
kubectl apply -f kubernetes/clearsessions-cronjob.yaml

# Проверьте CronJob
kubectl get cronjobs

# Посмотрите историю выполнения
kubectl describe cronjob clearsessions-cronjob

# Создайте тестовое задание для проверки (не дожидаясь расписания)
kubectl create job --from=cronjob/clearsessions-cronjob clearsessions-test

# Проверьте выполнение
kubectl get jobs
kubectl logs job/clearsessions-test
```

**Расписание CronJob:**

- По умолчанию: каждый день в 2:00 (UTC).
- Формат: `"0 2 * * *"` (cron синтаксис).
- Можно изменить в манифесте `kubernetes/clearsessions-cronjob.yaml`.

---

## Развертывание PostgreSQL в кластере с помощью Helm

**Цель**: Перенести базу данных PostgreSQL внутрь кластера Kubernetes, используя официальный **Helm**-чарт от Bitnami. Это более надёжный, воспроизводимый и удобный в обслуживании способ по сравнению с ручным созданием **Deployment** / **StatefulSet** / **PVC**.

### Предварительные требования

- **Helm 3** установлен.
- Доступ к кластеру (**Minikube**, **kind**, **k3s** или любой другой).
- Файл `.env` в корне проекта (создаётся на основе `.env.example`).

### Установка Helm

Если у вас ещё не установлен **Helm**, выполните следующие шаги:

#### Для macOS:

```bash
brew install helm
```

#### Для Linux:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### Проверка версии:

```bash
helm version
```

### Подготовка файла с переменными окружения

В репозитории есть файл **.env.example** — скопируйте его в **.env** и заполните своими значениями.

```bash
# Скопировать шаблон
cp .env.example .env
```

Откройте файл **.env** и укажите значения:

```env
# PostgreSQL настройки (используются для Helm-чарта)
POSTGRES_DB=test_k8s
POSTGRES_USER=test_k8s
POSTGRES_PASSWORD=ваш_надёжный_пароль_здесь

# Django настройки
WEB_SECRET_KEY=очень_длинный_и_случайный_ключ_здесь
WEB_DEBUG=FALSE
WEB_DATABASE_URL=postgres://test_k8s:ваш_пароль@postgresql:5432/test_k8s
WEB_ALLOWED_HOSTS=*
```

> **Важно**:  
> Файл **.env** никогда не должен попадать в **git**. Убедитесь, что **.env** добавлен в **.gitignore**.

### Удаление старой базы (если была установлена ранее)

Если вы ранее уже устанавливали PostgreSQL в кластер с помощью Helm или вручную, удалите старые ресурсы:

```bash
# Удаление Helm-релиза (если существует)
helm list
helm uninstall postgresql --ignore-not-found

# Удаление старых ресурсов, если БД создавалась вручную
kubectl delete deployment  postgres-deployment --ignore-not-found
kubectl delete service     postgres-service    --ignore-not-found
kubectl delete pvc         data-postgresql-0   --ignore-not-found
kubectl delete pvc         postgres-pvc        --ignore-not-found
```

> Рекомендация: После удаления релиза и **PVC** убедитесь, что старые **PersistentVolume** не остались "зависшими":

```bash
kubectl get pv | grep postgre
# Если есть — можно удалить вручную (осторожно!):
kubectl delete pv <имя-pv> --force --grace-period=0
```

### Добавление репозитория Bitnami

```bash
# Добавляем репозиторий Bitnami
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Установка PostgreSQL из Helm-чарта

```bash
# Загружаем переменные из .env
source .env

# Устанавливаем PostgreSQL
helm install postgresql bitnami/postgresql \
  --set auth.username="${POSTGRES_USER}" \
  --set auth.password="${POSTGRES_PASSWORD}" \
  --set auth.database="${POSTGRES_DB}" \
  --set primary.persistence.size=1Gi \
  --set auth.enablePostgresUser=false \
  --wait \
  --timeout 5m
```

### Проверка установки

```bash
# Статус релиза
helm status postgresql

# Поды
kubectl get pods -l app.kubernetes.io/name=postgresql

# Сервис
kubectl get svc postgresql

# Секрет с паролем (для отладки)
kubectl get secret postgresql -o jsonpath='{.data.password}' | base64 -d
```

### Проверка подключения к базе

```bash
# Получаем пароль из секрета (для пользователя POSTGRES_USER)
export PGPASSWORD=$(kubectl get secret postgresql -o jsonpath="{.data.password}" | base64 -d)

# Тестовое подключение
kubectl run -it --rm psql-test --image=postgres:16 --restart=Never \
  --env="PGPASSWORD=$PGPASSWORD" \
  -- psql -h postgresql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "SELECT version(); SELECT current_user;"
```

Ожидаемый результат:

```text
version
-------------------------------------
 PostgreSQL 18.1 on x86_64-pc-linux-gnu ...
 current_user
--------------
 test_k8s
```

### Обновление секрета Django (для подключения приложения)

```bash
# Удаляем старый секрет (если нужно обновить)
kubectl delete secret django-secret --ignore-not-found

# Создаём / обновляем секрет из .env
source .env
kubectl create secret generic django-secret \
  --from-literal=SECRET_KEY="${WEB_SECRET_KEY}" \
  --from-literal=DATABASE_URL="${WEB_DATABASE_URL}"
```

### Перезапуск приложения и применение миграций

```bash
# Перезапускаем deployment
kubectl rollout restart deployment django-app-deployment
kubectl rollout status deployment django-app-deployment

# Выполняем миграции
POD=$(kubectl get pods -l app=django-app -o name | head -1 | cut -d/ -f2)
kubectl exec -it "$POD" -- python manage.py migrate

# (опционально) Создаём суперпользователя
kubectl exec -it "$POD" -- python manage.py createsuperuser
```

### Полезные команды для работы с PostgreSQL в Helm

```bash
# Посмотреть все значения чарта
helm show values bitnami/postgresql

# Обновить настройки (например, размер диска)
helm upgrade postgresql bitnami/postgresql \
  --set primary.persistence.size=2Gi

# Посмотреть историю релизов
helm history postgresql

# Откат на предыдущую версию
helm rollback postgresql 1

# Полное удаление
helm uninstall postgresql
```

---

## Переменные окружения

Образ с Django считывает настройки из переменных окружения:

- **SECRET_KEY** — обязательная секретная настройка Django. Это соль для генерации хэшей. Значение может быть любым, важно лишь, чтобы оно никому не было известно. [Документация Django](https://docs.djangoproject.com/en/3.2/ref/settings/#secret-key).
  
- **DEBUG** — настройка Django для включения отладочного режима. Принимает значения **TRUE** или **FALSE**. [Документация Django](https://docs.djangoproject.com/en/3.2/ref/settings/#std:setting-DEBUG).
  
- **ALLOWED_HOSTS** — настройка