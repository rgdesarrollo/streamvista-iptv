#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  if (getenv("GDK_BACKEND") == nullptr) {
    gdk_set_allowed_backends("x11,wayland");
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
