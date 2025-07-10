import requests

url = "http://158.160.192.34:8081/api/generate"
payload = {
    "model": "gemma3:27b",
    "prompt": "Назови столицу Франции.",
    "stream": False
}

response = requests.post(url, json=payload, timeout=1000)
print(response.json())