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
m_dep = meson.get_compiler('c').find_library('m', required: false)

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
  files('src/agent_intents.vala', 'src/camera.vala', 'src/window.vala', 'src/app.vala') + [resources],
  dependencies: [gtk_dep, gee_dep, gst_dep, gstapp_dep, gstvideo_dep, posix_dep, m_dep, libsingularity_dep],
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

iride = find_program('iride', required: get_option('iride'))
if iride.found()
  custom_target('iride-icon',
    input: 'data/icons/iride/iride.json',
    output: 'dev.sinty.camera.iride',
    depend_files: files(
      'data/icons/iride/layers/000.svg',
      'data/icons/iride/layers/001.svg',
      'data/icons/iride/layers/002.svg',
      'data/icons/iride/layers/003.svg',
      'data/icons/iride/layers/004.svg',
      'data/icons/iride/layers/005.svg',
      'data/icons/iride/layers/006.svg',
      'data/icons/iride/layers/007.svg',
      'data/icons/iride/layers/008.svg',
      'data/icons/iride/layers/009.svg',
      'data/icons/iride/layers/010.svg',
      'data/icons/iride/layers/011.svg',
      'data/icons/iride/layers/012.svg',
      'data/icons/iride/layers/013.svg',
      'data/icons/iride/layers/014.svg',
      'data/icons/iride/layers/015.svg',
      'data/icons/iride/layers/016.svg',
      'data/icons/iride/layers/017.svg',
      'data/icons/iride/layers/018.svg',
      'data/icons/iride/layers/019.svg',
      'data/icons/iride/layers/020.svg',
      'data/icons/iride/layers/021.svg',
      'data/icons/iride/layers/022.svg',
      'data/icons/iride/layers/023.svg',
      'data/icons/iride/layers/024.svg',
      'data/icons/iride/layers/025.svg',
      'data/icons/iride/layers/026.svg',
      'data/icons/iride/layers/027.svg',
      'data/icons/iride/layers/028.svg',
      'data/icons/iride/layers/029.svg',
      'data/icons/iride/layers/030.svg',
      'data/icons/iride/layers/031.svg',
      'data/icons/iride/layers/032.svg',
      'data/icons/iride/layers/033.svg',
      'data/icons/iride/layers/034.svg',
      'data/icons/iride/layers/035.svg',
      'data/icons/iride/layers/036.svg',
      'data/icons/iride/layers/037.svg',
      'data/icons/iride/layers/038.svg',
      'data/icons/iride/layers/039.svg',
      'data/icons/iride/layers/040.svg',
      'data/icons/iride/layers/041.svg',
      'data/icons/iride/layers/042.svg',
      'data/icons/iride/layers/043.svg',
      'data/icons/iride/layers/044.svg',
      'data/icons/iride/layers/045.svg',
      'data/icons/iride/layers/046.svg',
      'data/icons/iride/layers/047.svg',
      'data/icons/iride/layers/048.svg',
      'data/icons/iride/layers/049.svg',
      'data/icons/iride/layers/050.svg',
      'data/icons/iride/layers/051.svg',
      'data/icons/iride/layers/052.svg',
      'data/icons/iride/layers/053.svg',
      'data/icons/iride/layers/054.svg',
      'data/icons/iride/layers/055.svg',
      'data/icons/iride/layers/056.svg',
      'data/icons/iride/layers/057.svg',
      'data/icons/iride/layers/058.svg',
      'data/icons/iride/layers/059.svg',
    ),
    command: [iride, 'build', meson.current_source_dir() / 'data' / 'icons' / 'iride', '@OUTPUT@'],
    install: true,
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
  )
endif
