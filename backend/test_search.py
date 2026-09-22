from services.research_engine import ResearchEngine
engine = ResearchEngine()
results = engine.search_web("summertime sadness lyrics")
for r in results:
    print(r['title'])
    print(r['snippet'])
