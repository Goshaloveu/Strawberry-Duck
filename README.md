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
* **Матчинг и Объединение**
