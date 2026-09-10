from setuptools import setup, find_packages

setup(
    name="conductor-runtime",
    version="1.0.4",
    description="NEURONIX Conductor Capability Runtime & Zero-Idle Socket Broker",
    author="NEURONIX Contributors",
    author_email="maintainers@neuronix.org",
    license="Apache-2.0",
    packages=find_packages(),
    install_requires=[
        "neuronix-core",
    ],
    entry_points={
        "console_scripts": [
            "conductor-runtime=conductor_runtime.cli:main",
        ],
    },
    classifiers=[
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3",
        "Topic :: System :: Operating System",
    ],
)
