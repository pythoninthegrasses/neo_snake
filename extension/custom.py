# godot-cpp SCons custom-options file (third_party/godot-cpp/SConstruct's own
# `customs = ["custom.py"]` mechanism), loaded automatically for every
# `scons -C extension` invocation. Values here are defaults only -- still
# overridable on the command line (e.g. `scons -C extension use_static_cpp=yes`).

# use_static_cpp's default (True) appends -static-libgcc -static-libstdc++,
# which requires a static libstdc++.a. Many distro toolchains (e.g. this
# repo's dev systems) ship only the shared libstdc++.so via the base gcc
# package, not the separate -static-libstdc++ dev package, so the default
# fails at link time with "cannot find -lstdc++". Dynamic linking against
# the near-universally-present libstdc++.so.6 is the more portable default
# here.
use_static_cpp = False
