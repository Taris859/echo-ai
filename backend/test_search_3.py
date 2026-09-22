import requests
headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
}
response = requests.get("https://html.duckduckgo.com/html/?q=summertime+sadness+lyrics", headers=headers, timeout=10)
print(response.status_code)
if response.status_code == 200:
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(response.text, 'html.parser')
    items = soup.find_all('div', class_='result__body')
    print("Found items:", len(items))
