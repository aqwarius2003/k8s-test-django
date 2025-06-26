# Django Site

Докеризированный сайт на Django для экспериментов с Kubernetes.

Внутри контейнера Django приложение запускается с помощью Nginx Unit, не путать с Nginx. Сервер Nginx Unit выполняет сразу две функции: как веб-сервер он раздаёт файлы статики и медиа, а в роли сервера-приложений он запускает Python и Django. Таким образом Nginx Unit заменяет собой связку из двух сервисов Nginx и Gunicorn/uWSGI. [Подробнее про Nginx Unit](https://unit.nginx.org/).

## Как подготовить окружение к локальной разработке

Код в репозитории полностью докеризирован, поэтому для запуска приложения вам понадобится Docker. Инструкции по его установке ищите на официальных сайтах:

- [Get Started with Docker](https://www.docker.com/get-started/)

Вместе со свежей версией Docker к вам на компьютер автоматически будет установлен Docker Compose. Дальнейшие инструкции будут его активно использовать.

## Как запустить сайт для локальной разработки

Запустите базу данных и сайт:

```shell
$ docker compose up
```

В новом терминале, не выключая сайт, запустите несколько команд:

```shell
$ docker compose run --rm web ./manage.py migrate  # создаём/обновляем таблицы в БД
$ docker compose run --rm web ./manage.py createsuperuser  # создаём в БД учётку суперпользователя
```

Готово. Сайт будет доступен по адресу [http://127.0.0.1:8080](http://127.0.0.1:8080). Вход в админку находится по адресу [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/).

## Как вести разработку

Все файлы с кодом django смонтированы внутрь докер-контейнера, чтобы Nginx Unit сразу видел изменения в коде и не требовал постоянно пересборки докер-образа -- достаточно перезапустить сервисы Docker Compose.

### Как обновить приложение из основного репозитория

Чтобы обновить приложение до последней версии подтяните код из центрального окружения и пересоберите докер-образы:

```shell
$ git pull
$ docker compose build
```

После обновлении кода из репозитория стоит также обновить и схему БД. Вместе с коммитом могли прилететь новые миграции схемы БД, и без них код не запустится.

Чтобы не гадать заведётся код или нет — запускайте при каждом обновлении команду `migrate`. Если найдутся свежие миграции, то команда их применит:

```shell
$ docker compose run --rm web ./manage.py migrate
…
Running migrations:
  No migrations to apply.
```

### Как добавить библиотеку в зависимости

В качестве менеджера пакетов для образа с Django используется pip с файлом requirements.txt. Для установки новой библиотеки достаточно прописать её в файл requirements.txt и запустить сборку докер-образа:

```sh
$ docker compose build web
```

Аналогичным образом можно удалять библиотеки из зависимостей.

<a name="env-variables"></a>
## Переменные окружения

Образ с Django считывает настройки из переменных окружения:

`SECRET_KEY` -- обязательная секретная настройка Django. Это соль для генерации хэшей. Значение может быть любым, важно лишь, чтобы оно никому не было известно. [Документация Django](https://docs.djangoproject.com/en/3.2/ref/settings/#secret-key).

`DEBUG` -- настройка Django для включения отладочного режима. Принимает значения `TRUE` или `FALSE`. [Документация Django](https://docs.djangoproject.com/en/3.2/ref/settings/#std:setting-DEBUG).

`ALLOWED_HOSTS` -- настройка Django со списком разрешённых адресов. Если запрос прилетит на другой адрес, то сайт ответит ошибкой 400. Можно перечислить несколько адресов через запятую, например `127.0.0.1,192.168.0.1,site.test`. [Документация Django](https://docs.djangoproject.com/en/3.2/ref/settings/#allowed-hosts).

`DATABASE_URL` -- адрес для подключения к базе данных PostgreSQL. Другие СУБД сайт не поддерживает. [Формат записи](https://github.com/jacobian/dj-database-url#url-schema).


## Развертывание сайта в Minikube

Для запуска проекта в Minikube вам потребуется установленный Minikube и `kubectl`. Инструкции по установке можно найти на официальных сайтах:

- [Install Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

Манифесты Kubernetes для развертывания Django-приложения находятся в директории `kubernetes/`.

### 1. Запуск Minikube и настройка окружения Docker

Убедитесь, что Minikube запущен, и настройте вашу оболочку для использования демона Docker Minikube:

```shell
$ minikube start
$ eval $(minikube docker-env)
```

### 2. Сборка Docker образа

Соберите Docker образ Django-приложения. Убедитесь, что вы находитесь в корневом каталоге проекта, где находится `Dockerfile`:

```shell
$ docker build -t django_app:latest .
```

Поскольку мы используем `imagePullPolicy: Never` в наших манифестах Kubernetes, образ должен быть доступен в кэше Minikube. После сборки образ автоматически будет доступен.

### 3. Развертывание PostgreSQL вне кластера

Для развертывания PostgreSQL вне кластера используется файл `docker-compose.yml`.
PostgreSQL будет работать на хост-машине. **Для этого Docker должен быть установлен на хост-машине.** Альтернативно, база данных может быть поднята на любом другом компьютере, главное, чтобы кластер Minikube мог достучаться до ее внешнего IP-адреса.

Убедитесь, что ваш `docker-compose.yml` настроен для привязки порта PostgreSQL к IP-адресу вашей хост-машины (например, `192.168.1.33:5432:5432`).
Отредактируйте `docker-compose.yml` под свои параметры. Например, замените 192.168.1.33 на ваш реальный внешний IP-адрес

Запустите PostgreSQL с помощью Docker Compose:

```shell
$ docker compose up -d postgres
```

### 4. Создание секретов Kubernetes

Для безопасного хранения чувствительных данных, таких как `SECRET_KEY`, `ALLOWED_HOSTS` и `DATABASE_URL`, мы будем использовать секреты Kubernetes.

Создайте файл `kubernetes/django-secret.yaml` со следующим содержимым. **Важно:** значения для `DB_USER`, `DB_PASSWORD` и других чувствительных данных должны быть закодированы в Base64.

Вы можете закодировать строку в Base64, используя команду `echo -n "ВАША_СТРОКА" | base64`. Например, для пароля `my_secret_password` команда будет `echo -n "my_secret_password" | base64`, что даст `bXlfc2VjcmV0X3Bhc3N3b3Jk`.

Пример содержимого `kubernetes/django-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: django-secret
type: Opaque
data:
  DATABASE_URL <закодированный_DATABASE_URL>
  SECRET_KEY: <закодированный_SECRET_KEY>
  ALLOWED_HOSTS: <закодированный_ALLOWED_HOSTS>
```

Замените `<закодированное_имя_пользователя_БД>`, `<закодированный_пароль_БД>`, `<закодированный_SECRET_KEY>` и `<закодированный_ALLOWED_HOSTS>` на ваши фактические закодированные значения.

Затем примените этот секрет в вашем кластере Kubernetes:

```shell
$ kubectl apply -f kubernetes/django-secret.yaml
```

Убедитесь, что секрет создан:

```shell
$ kubectl get secret django-secret -o yaml
```

**Важно:** Если вы изменили значения в файле `kubernetes/django-secret.yaml` и повторно применили его (`kubectl apply -f kubernetes/django-secret.yaml`), уже запущенные поды вашего приложения не подхватят эти изменения автоматически. Для того чтобы поды начали использовать новые значения секрета, необходимо выполнить rolling restart развертывания:

```shell
$ kubectl rollout restart deployment/django-app
```

### 5. Применение манифестов Kubernetes: Развертывание и Сервис

Примените манифесты развертывания и сервиса Django, которые находятся в директории `kubernetes/` вашего проекта.

Перед применением убедитесь, что в `kubernetes/django-deployment.yaml` настроены переменные окружения, включая те, что берутся из секрета (`SECRET_KEY`, `DATABASE_URL`, `ALLOWED_HOSTS`). Параметр `DEBUG` должен быть установлен в `FALSE`.

В `kubernetes/django-service.yaml` измените тип сервиса на `ClusterIP`, так как Ingress будет управлять внешним доступом.

Примените эти манифесты:

```shell
$ kubectl apply -f kubernetes/django-deployment.yaml
$ kubectl apply -f kubernetes/django-service.yaml
```

### 6. Включение Ingress в Minikube

Minikube по умолчанию имеет встроенный аддон Ingress. Включите его:

```shell
$ minikube addons enable ingress
```

### 7. Настройка Ingress для внешнего доступа

Для маршрутизации внешнего трафика к вашему Django-приложению через доменное имя, используйте Ingress.

Создайте файл `kubernetes/imgress.yaml` со следующим содержимым:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myingress
  annotations:
    nginx.ingress.kubernetes.io/add-base-url: 'true'
spec:
  rules:
    - host: star-burger.test
      http:
        paths:
          - pathType: Prefix
            path: /
            backend:
              service:
                name: django-clusterip
                port:
                  number: 80
```

Примените этот манифест Ingress:

```shell
$ kubectl apply -f kubernetes/imgress.yaml
```

### 8. Настройка файла hosts на хост-машине

Поскольку `star-burger.test` не является публично зарегистрированным доменом, вам необходимо сопоставить его с IP-адресом Minikube в файле `/etc/hosts` на вашей хост-машине.

Получите IP-адрес Minikube:

```shell
$ minikube ip
```

Добавьте следующую строку в ваш файл `/etc/hosts` (замените `<minikube-ip>` на реальный IP-адрес Minikube):

```
<minikube-ip> star-burger.test
```

Пример: `192.168.59.114 star-burger.test`

### 9. Выполнение миграций Django

После развертывания необходимо выполнить миграции базы данных. Найдите имя вашего пода Django и выполните команду миграции:

```shell
$ kubectl get pods -l app=django-app
# Найдите имя пода, например, django-app-xxxxxxxxxx-xxxxx
$ kubectl exec -it <django-pod-name> -- python manage.py migrate
$ kubectl exec -it <django-pod-name> -- python manage.py createsuperuser # По желанию, создайте суперпользователя
```

### 10. Доступ к сайту через Ingress

Теперь ваш сайт будет доступен по адресу:

```
http://star-burger.test
```

Админка будет доступна по адресу `http://star-burger.test/admin/`.