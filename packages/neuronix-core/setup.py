from setuptools import setup, find_packages

setup(
    name="neuronix-core",
    version="1.0.5",
    description="Canonical shared domain logic library for NEURONIX OS",
    author="NEURONIX Contributors",
    url="https://github.com/adamriofc/NeuronixOS",
    license="Apache-2.0",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "pyyaml>=6.0",
    ],
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3.13",
    ],
)
