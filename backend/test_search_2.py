import requests
headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Content-Type": "application/x-www-form-urlencoded"
}
response = requests.post("https://html.duckduckgo.com/html/", data={"q": "summertime sadness lyrics"}, headers=headers, timeout=10)
print(response.status_code)
print(response.text[:500])
