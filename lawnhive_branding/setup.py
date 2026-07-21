from setuptools import setup, find_packages

with open("requirements.txt") as f:
    install_requires = f.read().strip().split("\n")

setup(
    name="lawnhive_branding",
    version="0.0.1",
    description="LawnHive Workspace - Custom Branding",
    author="LawnHive",
    author_email="info@lawnhive.com",
    packages=find_packages(),
    zip_safe=False,
    include_package_data=True,
    install_requires=install_requires,
)
