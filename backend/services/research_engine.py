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

        # Fallback to duckduckgo_search
        try:
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                from duckduckgo_search import DDGS
                ddgs = DDGS()
                raw_results = list(ddgs.text(query, max_results=5))
                results = []
                for r in raw_results:
                    results.append({
                        "title": r.get("title", ""),
                        "url": r.get("href", ""),
                        "snippet": r.get("body", "")
                    })
                return results
        except Exception as e:
            print(f"DuckDuckGo search fallback failed: {e}")

        return []

