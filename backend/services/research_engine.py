import os
import requests
import urllib.parse
import re

class ResearchEngine:
    def __init__(self):
        self.tavily_key = os.getenv("TAVILY_API_KEY", "")
        self.duckduckgo_url = "https://html.duckduckgo.com/html/?q="

    def search_web(self, query: str) -> list:
        """
        Performs web search and returns list of dicts: {"title": str, "url": str, "snippet": str}
        """
        if self.tavily_key:
            # Use Tavily Search API
            url = "https://api.tavily.com/search"
            headers = {"Content-Type": "application/json"}
            payload = {
                "api_key": self.tavily_key,
                "query": query,
                "search_depth": "advanced",
                "max_results": 10
            }
            try:
                response = requests.post(url, json=payload, headers=headers)
                if response.status_code == 200:
                    results = response.json().get("results", [])
                    return [{"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("content", "")} for r in results]
            except Exception as e:
                print(f"Tavily search exception, falling back: {e}")

        # Fallback to free DuckDuckGo HTML parser
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Content-Type": "application/x-www-form-urlencoded"
        }
        try:
            response = requests.post("https://html.duckduckgo.com/html/", data={"q": query}, headers=headers, timeout=10)
            if response.status_code == 200:
                html = response.text
                results = []
                try:
                    from bs4 import BeautifulSoup
                    soup = BeautifulSoup(html, 'html.parser')
                    items = soup.find_all('div', class_='result__body')
                    for item in items[:10]:
                        title_tag = item.find('a', class_='result__a')
                        if not title_tag:
                            continue
                        raw_url = title_tag.get('href', '')
                        if 'uddg=' in raw_url:
                            url = urllib.parse.unquote(raw_url.split('uddg=')[1].split('&')[0])
                        else:
                            url = raw_url
                        snippet_tag = item.find('a', class_='result__snippet')
                        snippet = snippet_tag.get_text(strip=True) if snippet_tag else ""
                        results.append({
                            "title": title_tag.get_text(strip=True),
                            "url": url,
                            "snippet": snippet
                        })
                except Exception as parse_e:
                    # Fallback regex parsing if bs4 is unavailable or fails
                    raw_matches = re.findall(r'<a class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>', html, re.DOTALL)
                    snippets = re.findall(r'<a class="result__snippet"[^>]*>(.*?)</a>', html, re.DOTALL)
                    for i in range(min(10, len(raw_matches))):
                        raw_url, title_html = raw_matches[i]
                        if 'uddg=' in raw_url:
                            url = urllib.parse.unquote(raw_url.split('uddg=')[1].split('&')[0])
                        else:
                            url = raw_url
                        clean_title = re.sub(r'<[^>]+>', '', title_html).strip()
                        clean_snippet = re.sub(r'<[^>]+>', '', snippets[i]).strip() if i < len(snippets) else ""
                        results.append({
                            "title": clean_title,
                            "url": url,
                            "snippet": clean_snippet
                        })
                return results
        except Exception as e:
            print(f"DuckDuckGo search fallback failed: {e}")

        return []

