import sys
import os
import exhale
# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
# import os
# import sys
# sys.path.insert(0, os.path.abspath('../include/fields2cover'))


# -- Project information -----------------------------------------------------

project = 'Fields2Cover'
copyright = '2020-2024, Wageningen University'
author = 'Wageningen University'

# The full version, including alpha/beta/rc tags
release = 'latest'

primary_domain = 'cpp'
highlight_language = 'cpp'


# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.intersphinx',
    'sphinx.ext.autosectionlabel',
    'sphinx.ext.todo',
    'sphinx.ext.coverage',
    'sphinx.ext.mathjax',
    'sphinx.ext.ifconfig',
    'sphinx.ext.viewcode',
    'sphinx_sitemap',
    'sphinx_code_tabs',
    'sphinx.ext.inheritance_diagram',
    "exhale",
    "breathe",
    "m2r2"
]


source_suffix = [".rst", ".md"]

breathe_projects = {"Fields2Cover": "../build/docs/doc_doxygen/xml"}
breathe_default_project = "Fields2Cover"
#breathe_default_members = ('members', 'undoc-members')
exhale_args =  {
    "containmentFolder"    : "./api/",
    "rootFileName"         : "f2c_library.rst",
    "rootFileTitle"        : "C++ API",
    "doxygenStripFromPath" : ".."
}

# Make the SWIG-generated python module importable for autodoc on the
# "Python API" pages. The docs CMake target sets this to the build tree;
# set it manually when running sphinx-build by hand.
f2c_python_dir = os.environ.get("F2C_PYTHON_DIR")
if f2c_python_dir:
    sys.path.insert(0, f2c_python_dir)


def _write_python_api_pages():
    """Generate one page per module of the python API into
    source/python_api/, mirroring the structure of the C++ reference
    (like exhale generates api/ for C++). Skipped when the SWIG module
    is not importable."""
    import shutil
    gen_dir = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "source", "python_api")
    shutil.rmtree(gen_dir, ignore_errors=True)
    try:
        import fields2cover as f2c
    except ImportError:
        return
    import inspect

    members = inspect.getmembers(f2c)
    classes = [n for n, o in members
               if inspect.isclass(o)
               and not n.startswith("_") and n != "SwigPyIterator"]
    functions = [n for n, o in members
                 if inspect.isfunction(o) and not n.startswith("_")]
    def in_group(name, prefix, extras=()):
        return name.startswith(prefix) or name in extras

    def is_container(name):
        return (name.startswith(("Vector", "optional_"))
                or name == "LongLongVector")

    grouped = set()

    def group(prefix, extras=()):
        names = [n for n in classes if in_group(n, prefix, extras)]
        grouped.update(names)
        return names

    groups = [
        ("0_functions", "Functions", "function", functions),
        ("2_objective_functions", "Objective functions", "class",
         group("OBJ_", ("PPObjective", "RPObjective"))),
        ("3_headland_generator", "Headland generator", "class",
         group("HG_", ("HeadlandGeneratorBase",))),
        ("4_swath_generator", "Swath generator", "class",
         group("SG_", ("SwathGeneratorBase",))),
        ("5_route_planning", "Route planning", "class", group("RP_")),
        ("6_path_planning", "Path planning", "class", group("PP_")),
        ("7_decomposition", "Decomposition", "class",
         group("DECOMP_", ("DecompositionBase",))),
        ("8_containers", "Containers", "class",
         [n for n in classes if is_container(n)]),
    ]
    groups.insert(1, ("1_types", "Types", "class",
                      [n for n in classes
                       if n not in grouped and not is_container(n)]))

    os.makedirs(gen_dir, exist_ok=True)
    for filename, title, kind, names in groups:
        if not names:
            continue
        with open(os.path.join(gen_dir, filename + ".rst"), "w") as page:
            page.write(title + "\n" + "=" * len(title) + "\n")
            for name in names:
                page.write("\n.. auto{}:: fields2cover.{}\n".format(kind, name))
                if kind == "class":
                    page.write("   :members:\n   :undoc-members:\n")


_write_python_api_pages()

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = 'sphinx_rtd_theme'

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
#html_static_path = ['_static']

html_baseurl = 'https://fields2cover.github.io/'
html_logo = "figures/logo_fields2cover.png"
html_favicon = "figures/favicon/favicon.ico"
html_theme_options = {
    'logo_only': True,
    'display_version': False,
}
github_url = 'https://www.github.com/Fields2Cover/Fields2Cover'

import time
def setup(app):
    time.sleep(3)




