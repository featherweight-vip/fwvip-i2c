# Sphinx configuration for the fwvip-i2c documentation.
#
# Build:  dfm run docs              (sphinx-build -W: a warning fails the build)
#    or:  sphinx-build -W -b html docs docs/_build/html

project = "fwvip-i2c"
copyright = "2026, Featherweight-VIP"
author = "Featherweight-VIP"
release = "0.1.0"

extensions = [
    "myst_parser",
    "sphinx_copybutton",
]

source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "fieldlist",
]
myst_heading_anchors = 3

exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]

html_theme = "furo"
html_title = "fwvip-i2c — I2C Verification IP"
html_static_path = ["_static"]

# Untagged code fences are plain text (diagrams, transcripts); SystemVerilog
# blocks tag themselves.
highlight_language = "text"
pygments_style = "friendly"
pygments_dark_style = "monokai"
