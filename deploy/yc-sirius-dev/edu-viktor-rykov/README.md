# Развертывание в Yandex Cloud (Sirius-Dev)

## Описание окружения

- **Кластер:** yc-sirius-dev
- **Namespace:** edu-viktor-rykov
- **Тип окружения:** Development
- **Репозиторий:** https://github.com/aqwarius2003/k8s-test-django

## Структура

- `manifests/` - Kubernetes манифесты
- `scripts/` - Скрипты деплоя

## Быстрые команды

```bash
# Переключиться на правильный кластер
kubectl config use-context yc-sirius-dev

# Переключиться на namespace
kubectl config set-context --current --namespace=edu-viktor-rykov

# Посмотреть все ресурсы
kubectl get all
```

## Уже запущенные ресурсы

- Deployment: `main-nginx`
- Service: `main-nginx` (NodePort)
- Pod: `main-nginx-78d4b58bdc-2b8gx`
```