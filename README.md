# Strawberry-Duck

# Popular Named Entity Tracker

---

### Project Goal

This project aims to develop a service that **identifies and tracks trending named entities** from online news sources. The core idea is to automatically extract named entities (people, organizations, locations, etc.) from published news articles, group identical entities, and count their frequency of appearance. Based on this frequency data, the service will then **predict which entities are likely to gain or lose popularity** in the future.

### Key Features

* **Data Collection:** Automated collection of news articles from various online sources, including Telegram channels and major news outlets.
* **Named Entity Recognition (NER):** Identification of named entities within collected text data for both Russian and English languages.
* **Entity Matching & Consolidation:** Intelligent grouping of identical or highly similar named entities to ensure accurate counting.
* **Popularity Tracking:** Continuous counting and aggregation of named entity occurrences over defined time periods.
* **Popularity Prediction:** Implementation of a machine learning model to forecast future trends in entity popularity.
* **Visualization:** Interactive dashboards to display:
    * Currently most popular named entities.
    * Entities with the highest recent increase in popularity.
    * Entities predicted to be most popular in the future.
    * Historical popularity graphs for individual entities.

---

# Сервис Выявления Популярных Именованных Сущностей

## Цель Проекта

Цель данного проекта — разработать сервис, который будет **выявлять и отслеживать набирающие популярность именованные сущности** на основе новостей, публикуемых в интернете. Основная идея заключается в автоматическом извлечении именованных сущностей (людей, организаций, географических объектов и т.д.) из новостных статей, объединении одинаковых сущностей и подсчете частоты их встречаемости. На основании этих данных сервис будет **строить предсказания о том, какие сущности будут набирать или терять популярность** в будущем.

### Ключевые Возможности

* **Сбор Данных:** Автоматический сбор новостных статей из различных онлайн-источников, включая Telegram-каналы и крупные новостные издания.
* **Выявление Именованных Сущностей (NER):** Идентификация именованных сущностей в собранном текстовом контенте для русского и английского языков.
* **Матчинг и Объединение Сущностей:** Интеллектуальное группирование идентичных или очень похожих именованных сущностей для точного подсчета.
* **Отслеживание Популярности:** Непрерывный подсчет и агрегация частоты встречаемости именованных сущностей за определенные временные периоды.
* **Прогнозирование Популярности:** Реализация модели машинного обучения для прогнозирования будущих тенденций популярности сущностей.
* **Визуализация:** Интерактивные панели для отображения:
    * Списка самых популярных именованных сущностей в текущий момент.
    * Списка сущностей, которые больше всего прибавили в популярности за последний период.
    * Списка сущностей, которые, согласно прогнозу модели, будут наиболее популярны в будущем.
    * Графиков исторической популярности для каждой отдельной сущности.

### Текущее состояние проекта

На данный момент мы реализуем MVP (минимально жизнеспособный продукт), который в последствии попытаемся докрутить до нужного нам состояния. Для этого мы реализуем сбор данных из источников с помощью скраппера, выделение ключевых слов с помощью нейросетевой квантизированной модели NER, матчинг похожих слов, а также подсчет статистик, предсказание популярности именнованных сущностей и визуализацию данных в интерфейсе сервиса DataLens.

### Схема данных БД проекта

<img src="https://github.com/Goshaloveu/Strawberry-Duck/blob/main/images/main_db_schema.png?raw=true" alt="Схема БД" style="width:50%; height:auto; display:inline-block; margin: center auto; max-width: 300px;">

### Архитектура проекта

<img src="https://github.com/Goshaloveu/Strawberry-Duck/blob/main/images/architecture.png?raw=true" alt="Схема БД" style="width:50%; height:auto; display:inline-block; margin: center auto; max-width: 300px;">


### Запуск

Для запуска проекта потрубется склонировать проект на свою машину, проверить имеется ли уже docker и docker-compose уже на компьютере, после чего запустить проект с помощью команды "docker-compose up -d"