#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <vector>
#include <mutex>
#include <map>

#include "flutter/generated_plugin_registrant.h"

// We no longer include texture_manager.h directly to avoid duplicate instances
// #include "../packages/native_onnx/linux/texture_manager.h"
#include <GL/gl.h>

// ========================================
// VIDEO TEXTURE PROVIDER
// ========================================

// Forward declarations
typedef struct _VideoTextureGL VideoTextureGL;
typedef struct _VideoTextureGLClass VideoTextureGLClass;

// Define type before using in macro
#define VIDEO_TEXTURE_GL_TYPE (video_texture_gl_get_type())
#define VIDEO_TEXTURE_GL(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), VIDEO_TEXTURE_GL_TYPE, VideoTextureGL))

// Custom texture type for video rendering
struct _VideoTextureGL {
  FlTextureGL parent_instance;
  int texture_manager_id;  // ID in TextureManager
  GMutex* mutex;
};

struct _VideoTextureGLClass {
  FlTextureGLClass parent_class;
};

G_DEFINE_TYPE(VideoTextureGL, video_texture_gl, fl_texture_gl_get_type())

// Callback: populate GL texture for Flutter
// We need to declare this extern BEFORE usage if we use it here
extern "C" uint32_t Texture_GetGLHandle(int texture_id);
extern "C" int Texture_GetDimensions(int texture_id, int* width, int* height);
extern "C" int Texture_UploadPending(int texture_id);

static gboolean video_texture_gl_populate(FlTextureGL* texture,
                                          uint32_t* target,
                                          uint32_t* name,
                                          uint32_t* width,
                                          uint32_t* height,
                                          GError** error) {
  VideoTextureGL* self = VIDEO_TEXTURE_GL(texture);
  
  // Upload any pending frame data to GL texture (this is the UI thread with GL context!)
  Texture_UploadPending(self->texture_manager_id);
  
  // Use shared wrapper to get GL handle
  uint32_t gl_id = Texture_GetGLHandle(self->texture_manager_id);
  
  if (gl_id == 0) {
       // If texture not ready, return 0/empty to avoid rendering artifacts (like the UI itself)
       *target = GL_TEXTURE_2D;
       *name = 0; 
       *width = 0;
       *height = 0;
       return TRUE;
  }

  *target = GL_TEXTURE_2D;
  *name = gl_id;
  
  // Get actual dimensions from TextureManager
  int actual_width = 1920;
  int actual_height = 1080;
  if (Texture_GetDimensions(self->texture_manager_id, &actual_width, &actual_height) != 0) {
      // Fallback if dimensions not available
      actual_width = 1920;
      actual_height = 1080;
  }
  *width = actual_width;
  *height = actual_height;
  
  return TRUE;
}

static void video_texture_gl_dispose(GObject* object) {
  VideoTextureGL* self = VIDEO_TEXTURE_GL(object);
  
  if (self->mutex) {
    g_mutex_clear(self->mutex);
    g_free(self->mutex);
    self->mutex = nullptr;
  }
  
  G_OBJECT_CLASS(video_texture_gl_parent_class)->dispose(object);
}

static void video_texture_gl_class_init(VideoTextureGLClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = video_texture_gl_populate;
  G_OBJECT_CLASS(klass)->dispose = video_texture_gl_dispose;
}

static void video_texture_gl_init(VideoTextureGL* self) {
  self->texture_manager_id = 0;
  self->mutex = g_new0(GMutex, 1);
  g_mutex_init(self->mutex);
}

static VideoTextureGL* video_texture_gl_new(int texture_manager_id) {
  VideoTextureGL* texture = VIDEO_TEXTURE_GL(
    g_object_new(VIDEO_TEXTURE_GL_TYPE, nullptr)
  );
  texture->texture_manager_id = texture_manager_id;
  return texture;
}

// ========================================
// METHOD CHANNEL HANDLING
// ========================================

static FlTextureRegistrar* g_texture_registrar = nullptr;
static std::map<int64_t, VideoTextureGL*> g_texture_objects;  // Store texture objects
static std::mutex g_texture_map_mutex;

// Extern function from inference_bridge.cpp
extern "C" void Video_SetTextureManagerId(long long session_id, int texture_manager_id);
// New exported wrappers from inference_bridge.cpp (plugin)
extern "C" int Texture_Create(int width, int height); 
extern "C" uint32_t Texture_GetGLHandle(int texture_id);

// Handle method calls from Dart
static void handle_texture_method_call(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  
  if (strcmp(method, "createVideoTexture") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    int width = fl_value_get_int(fl_value_lookup_string(args, "width"));
    int height = fl_value_get_int(fl_value_lookup_string(args, "height"));
    
    g_print("[TEXTURE-CHANNEL] Creating texture %dx%d\n", width, height);
    
    // Create texture using shared plugin instance
    int tex_mgr_id = Texture_Create(width, height);
    
    if (tex_mgr_id <= 0) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("CREATE_FAILED", "Failed to create texture in TextureManager", nullptr)
      );
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    
    // Get GL ID for populating the texture
    // We can't do this later inside populate easily, so we rely on TextureManager keeping it valid
    // For now, video_texture_gl_populate uses id lookup on populate()
    // But we need to make sure video_texture_gl_populate also uses the shared instance helper
    // OR we modify populate to call Texture_GetGLHandle?
    // Let's modify video_texture_gl_populate next. For now, this part is just creation.
    
    // Create VideoTextureGL wrapper
    VideoTextureGL* video_tex = video_texture_gl_new(tex_mgr_id);
    
    // Register with Flutter
    if (!fl_texture_registrar_register_texture(g_texture_registrar, FL_TEXTURE(video_tex))) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("REGISTER_FAILED", "Failed to register texture with Flutter", nullptr)
      );
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    
    // Get texture ID (use GObject pointer as ID)
    int64_t flutter_texture_id = reinterpret_cast<int64_t>(video_tex);
    
    // Store texture object
    {
      std::lock_guard<std::mutex> lock(g_texture_map_mutex);
      g_texture_objects[flutter_texture_id] = video_tex;
    }
    
    g_print("[TEXTURE-CHANNEL] Created Flutter texture %ld (TextureManager ID: %d)\n",
            flutter_texture_id, tex_mgr_id);
    
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "textureId", fl_value_new_int(flutter_texture_id));
    fl_value_set_string_take(result, "textureManagerId", fl_value_new_int(tex_mgr_id));
    
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  if (strcmp(method, "updateTexture") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
   int64_t texture_id = fl_value_get_int(fl_value_lookup_string(args, "textureId"));
    
    std::lock_guard<std::mutex> lock(g_texture_map_mutex);
    auto it = g_texture_objects.find(texture_id);
    if (it == g_texture_objects.end()) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NOT_FOUND", "Texture not found", nullptr)
      );
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    
    // Mark texture as needing update
    fl_texture_registrar_mark_texture_frame_available(
      g_texture_registrar,
      FL_TEXTURE(it->second)
    );
    
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  if (strcmp(method, "connectStreamToTexture") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    int64_t video_id = fl_value_get_int(fl_value_lookup_string(args, "videoId"));
    int texture_manager_id = fl_value_get_int(fl_value_lookup_string(args, "textureManagerId"));
    
    // Store this mapping - the video will update this texture
    g_print("[TEXTURE-CHANNEL] Connecting video %ld to texture manager %d\n",
            video_id, texture_manager_id);
            
    // Call into native_onnx to set mapping
    Video_SetTextureManagerId(video_id, texture_manager_id);
    
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}


struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "smart_store_linux");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "smart_store_linux");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // ========================================
  // TEXTURE INTEGRATION SETUP
  // ========================================
  
  // Create a plugin registrar for texture management
  g_autoptr(FlPluginRegistrar) texture_plugin_registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view), "TexturePlugin");
  
  // Get texture registrar from plugin registrar
  g_texture_registrar = fl_plugin_registrar_get_texture_registrar(texture_plugin_registrar);
  g_print("[TEXTURE-INIT] Flutter texture registrar initialized\n");
  
  // Create method channel for texture operations
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) texture_channel = fl_method_channel_new(
    fl_engine_get_binary_messenger(fl_view_get_engine(view)),
    "native_onnx/texture",
    FL_METHOD_CODEC(codec)
  );
  
  fl_method_channel_set_method_call_handler(
    texture_channel,
    handle_texture_method_call,
    g_object_ref(view),  // Pass view as user_data
    g_object_unref       // Cleanup function
  );
  
  g_print("[TEXTURE-INIT] Method channel 'native_onnx/texture' registered\n");

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
