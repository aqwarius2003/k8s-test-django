FROM nginx/unit:1.25.0-python3.9
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DJANGO_SETTINGS_MODULE=webapp.settings
ENV DEBUG=False

WORKDIR /webapp
COPY requirements.txt /webapp/
RUN apt update && apt install -y python3-pip                                  \
    && pip3 install -r requirements.txt                                       \
    && apt remove -y python3-pip                                              \
    && apt autoremove --purge -y                                              \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/*.list
COPY unit_config.json /docker-entrypoint.d/
COPY src /webapp/src
WORKDIR /webapp/src
RUN export SECRET_KEY=django-insecure-dummy-key-for-dev-123 && python manage.py collectstatic --noinput
EXPOSE 80
VOLUME ["/media"]
