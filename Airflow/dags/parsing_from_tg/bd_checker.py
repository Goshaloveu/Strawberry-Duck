import sqlite3

conn = sqlite3.connect('telegram_posts.db')
cursor = conn.cursor()

# Показать все посты
cursor.execute("SELECT * FROM posts ORDER BY publication_date DESC")
posts = cursor.fetchall()

for post in posts:
    print(f"ID: {post[0]}, Источник: {post[1]}")
    print(f"Дата: {post[3]}")
    print(f"Текст: {post[2][:100]}...")
    print("-" * 50)

conn.close()