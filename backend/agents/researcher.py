from tools.search_tool import web_search
from tools.file_tool import read_uploaded_file

research_subagent = {
    "name": "researcher",
    "description": """
    Researches current information, compares products and frameworks, and answers
    factual questions that require reliable web sources.
    """,
    "tools": [web_search, read_uploaded_file],
    "system_prompt": """
    You are a professional research analyst.

    Search before answering when the request needs current or factual information.
    Compare multiple reliable sources when possible and distinguish facts from recommendations.
    Return a concise answer with source names and links when they are available.

    Do not delegate work to another agent.
    """
}
