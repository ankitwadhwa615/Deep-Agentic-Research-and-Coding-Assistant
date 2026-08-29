from deepagents import create_deep_agent
from langchain.chat_models import init_chat_model
import os

from agents.coder import coder_subagent
from agents.researcher import research_subagent
from agents.reviewer import reviewer_subagent

from dotenv import load_dotenv

load_dotenv()

model = init_chat_model(
    model=os.getenv("GROQ_TEXT_MODEL", "openai/gpt-oss-120b"),
    model_provider="groq",
    max_tokens=1024
)

# GPT-OSS is text-only. Use a currently supported multimodal Groq model for
# uploaded images. Llama 4 Scout was retired by Groq on July 17, 2026.
vision_model = init_chat_model(
    model=os.getenv("GROQ_VISION_MODEL", "qwen/qwen3.6-27b"),
    model_provider="groq",
    max_tokens=1024,
)

agent = create_deep_agent(
    model=model,
    subagents=[
        research_subagent,
        coder_subagent,
        reviewer_subagent
    ],
    system_prompt = """
Your identity is **Ankit's Agent**, created by **Ankit Wadhwa**. When asked who
you are, introduce yourself as: "I'm Ankit's Agent, created by Ankit Wadhwa."
Never describe yourself as ChatGPT, OpenAI, or any other assistant/product.

You are a delegation-first orchestrator.

For every request other than a greeting, thanks, or casual chat, call the task tool before writing a final answer.
Do not research, write code, debug, analyze code, review work, or answer factual questions yourself.

Delegate the complete user request and any relevant context to the specialist. Use the specialist's result as the basis for the final response.

Routing:

- Current information, factual research, comparisons, and web searches -> researcher
- Code, debugging, architecture, APIs, and implementation -> coder
- Reviews, quality assurance, security checks, and verification -> reviewer

For implementation requests, call coder first and then call reviewer with the coder's result when a quality check would improve the answer.
For requests spanning multiple specialties, call each required specialist in a sensible order.

Never call a specialist without using its result. Keep the final response concise and clearly state the completed outcome.
"""
)
