project('singularity-camera', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-camera"', language: 'c')
subdir('po')

gtk_dep   = dependency('gtk4')
gee_dep   = dependency('gee-0.8')
gst_dep   = dependency('gstreamer-1.0')
gstapp_dep = dependency('gstreamer-app-1.0')
gstvideo_dep = dependency('gstreamer-video-1.0')
posix_dep = meson.get_compiler('vala').find_library('posix')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-camera-resources',
  'resources/dev.sinty.camera.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

executable('singularity-camera',
  files('src/camera.vala', 'src/window.vala', 'src/app.vala') + [resources],
  dependencies: [gtk_dep, gee_dep, gst_dep, gstapp_dep, gstvideo_dep, posix_dep, libsingularity_dep],
  install: true
)

shared_module('camera-indicator',
  files('plugin/camera_indicator.vala', 'plugin/camera_users.vala'),
  dependencies: [gtk_dep, gee_dep, posix_dep, libsingularity_dep, dependency('libpeas-2'), dependency('gio-unix-2.0')],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'camera-indicator'
)
install_data('plugin/camera-indicator.plugin',
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'camera-indicator'
)

camera_users_test = executable('camera-users-test',
  files('tests/camera_users_test.vala', 'plugin/camera_users.vala'),
  dependencies: [gee_dep, posix_dep, dependency('gio-unix-2.0'), libsingularity_dep],
)
test('camera-users', camera_users_test, env: ['TMPDIR=' + meson.current_build_dir()])

install_data('data/dev.sinty.camera.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.camera.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
