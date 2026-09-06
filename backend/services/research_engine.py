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
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
        encoded_query = urllib.parse.quote(query)
        try:
            response = requests.get(f"{self.duckduckgo_url}{encoded_query}", headers=headers)
            if response.status_code == 200:
                html = response.text
                # Simple regex extraction of titles, snippets and URLs from DuckDuckGo HTML page
                # In DuckDuckGo HTML, results are inside <td class="result-snippet"> or search result links
                links = re.findall(r'<a class="result__url" href="([^"]+)"', html)
                snippets = re.findall(r'<a class="result__snippet"[^>]*>(.*?)</a>', html, re.DOTALL)
                titles = re.findall(r'<a class="result__link"[^>]*>(.*?)</a>', html, re.DOTALL)
                
                results = []
                for i in range(min(5, len(links), len(snippets))):
                    clean_snippet = re.sub(r'<[^>]+>', '', snippets[i]).strip()
                    clean_title = re.sub(r'<[^>]+>', '', titles[i]).strip()
                    results.append({
                        "title": clean_title,
                        "url": links[i],
                        "snippet": clean_snippet
                    })
                return results
        except Exception as e:
            print(f"DuckDuckGo search fallback failed: {e}")

        return []
