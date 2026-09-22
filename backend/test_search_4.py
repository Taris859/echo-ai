from duckduckgo_search import DDGS
ddgs = DDGS()
results = list(ddgs.text("summertime sadness lyrics", max_results=3))
for r in results:
    print(r)
