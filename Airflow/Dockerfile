FROM apache/airflow:2.7.1

WORKDIR /opt/airflow

USER root
RUN apt update && apt -y install procps default-jre

USER airflow
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt