from langchain_core.tools import tool
import os
from tavily import TavilyClient

@tool(description="Search the internet for current information, news, and factual research.")
def web_search(query: str) -> str:
    api_key = os.getenv("TAVILY_API_KEY")

    if not api_key:
        return "TAVILY_API_KEY is not configured."

    client = TavilyClient(api_key=api_key)
    result = client.search(query, max_results=5)

    return str(result)
