from setuptools import setup, find_packages

setup(
    name="conductor-mcp",
    version="1.0.4",
    description="NEURONIX Model Context Protocol (MCP 2026-07-28) Universal Adapter for Conductor",
    author="NEURONIX Contributors",
    author_email="maintainers@neuronix.org",
    license="Apache-2.0",
    packages=find_packages(),
    install_requires=[
        "neuronix-core",
        "conductor-runtime",
    ],
    entry_points={
        "console_scripts": [
            "conductor-mcp=conductor_mcp.server:main",
        ],
    },
    classifiers=[
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3",
        "Topic :: System :: Operating System",
    ],
)
