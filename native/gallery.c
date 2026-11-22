/* =============================================================================
 *  ZENITH GALLERY: Cinematic 70/30 Widescreen Wallpaper Shower
 * =============================================================================
 *  • Top 65-70%: High-Res 16:9 Hero Preview with rounded corners & accent border
 *  • Bottom 25-30%: Horizontal Filmstrip Carousel with category badge chips
 *  • Pure C with GTK4 & Cairo. Multi-threaded thumbnail loading & LRU caching.
 * =============================================================================
 */

#define _GNU_SOURCE
#include <gtk/gtk.h>
#include <cairo.h>
#include <json-c/json.h>
#include <math.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <dirent.h>

typedef struct {
    char *path;
    char *category;
    char *stem;
} WallpaperItem;

typedef struct {
    cairo_surface_t *surface;
    guint64 last_used;
} CachedSurface;

typedef struct {
    int index;
    double x, y, w, h;
} CardBounds;

typedef struct App App;

typedef struct {
    App *app;
    char *key;
    char *path;
    int target_w, target_h;
    cairo_surface_t *surface;
} ThumbnailJob;

struct App {
    GtkApplication *application;
    GtkWidget *window;
    GtkWidget *drawing_area;
    GPtrArray *items;
    GPtrArray *filtered;
    GPtrArray *categories;
    GHashTable *cache;
    GHashTable *pending;
    GThreadPool *workers;
    int index;
    int category_index;
    double position;
    double target_position;
    double accent[3];
    guint tick_id;
    guint64 serial;
    gboolean alive;
    gboolean applying;
    CardBounds bounds[32];
    int n_bounds;
};

static void queue_prewarm(App *a);

static void draw_rounded_rect(cairo_t *cr, double x, double y, double w, double h, double r) {
    r = fmin(r, fmin(w / 2.0, h / 2.0));
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -G_PI / 2.0, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, G_PI / 2.0);
    cairo_arc(cr, x + r, y + h - r, r, G_PI / 2.0, G_PI);
    cairo_arc(cr, x + r, y + r, r, G_PI, 3.0 * G_PI / 2.0);
    cairo_close_path(cr);
}

static void surface_cache_destroy(gpointer p) {
    CachedSurface *c = (CachedSurface *)p;
    if (c->surface) cairo_surface_destroy(c->surface);
    g_free(c);
}

static gboolean on_thumbnail_completed(gpointer data) {
    ThumbnailJob *j = (ThumbnailJob *)data;
    App *a = j->app;
    g_hash_table_remove(a->pending, j->key);

    if (a->alive) {
        if (g_hash_table_size(a->cache) >= 96) {
            GHashTableIter iter;
            gpointer k, v;
            guint64 oldest = G_MAXUINT64;
            char *victim = NULL;
            g_hash_table_iter_init(&iter, a->cache);
            while (g_hash_table_iter_next(&iter, &k, &v)) {
                CachedSurface *c = (CachedSurface *)v;
                if (c->last_used < oldest) {
                    oldest = c->last_used;
                    victim = (char *)k;
                }
            }
            if (victim) g_hash_table_remove(a->cache, victim);
        }

        CachedSurface *c = g_new0(CachedSurface, 1);
        c->surface = j->surface;
        c->last_used = ++a->serial;
        g_hash_table_replace(a->cache, g_strdup(j->key), c);

        if (a->drawing_area) gtk_widget_queue_draw(a->drawing_area);
    } else if (j->surface) {
        cairo_surface_destroy(j->surface);
    }

    g_free(j->key);
    g_free(j->path);
    g_free(j);
    return G_SOURCE_REMOVE;
}

static void worker_thumbnail_job(gpointer data, gpointer unused) {
    (void)unused;
    ThumbnailJob *j = (ThumbnailJob *)data;
    
    GError *error = NULL;
    GdkPixbuf *pb = gdk_pixbuf_new_from_file_at_scale(j->path, j->target_w, j->target_h, FALSE, &error);
    cairo_surface_t *surf = NULL;

    if (pb) {
        int w = gdk_pixbuf_get_width(pb);
        int h = gdk_pixbuf_get_height(pb);
        int rowstride = gdk_pixbuf_get_rowstride(pb);
        guchar *pixels = gdk_pixbuf_get_pixels(pb);
        gboolean has_alpha = gdk_pixbuf_get_has_alpha(pb);

        surf = cairo_image_surface_create(has_alpha ? CAIRO_FORMAT_ARGB32 : CAIRO_FORMAT_RGB24, w, h);
        cairo_surface_flush(surf);
        guchar *dest = cairo_image_surface_get_data(surf);
        int dest_stride = cairo_image_surface_get_stride(surf);

        for (int y = 0; y < h; y++) {
            guchar *src_row = pixels + y * rowstride;
            guint32 *dst_row = (guint32 *)(dest + y * dest_stride);
            for (int x = 0; x < w; x++) {
                guchar r = src_row[x * (has_alpha ? 4 : 3) + 0];
                guchar g = src_row[x * (has_alpha ? 4 : 3) + 1];
                guchar b = src_row[x * (has_alpha ? 4 : 3) + 2];
                guchar a = has_alpha ? src_row[x * 4 + 3] : 255;
                dst_row[x] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }
        cairo_surface_mark_dirty(surf);
        g_object_unref(pb);
    }

    j->surface = surf;
    g_idle_add(on_thumbnail_completed, j);
}

static cairo_surface_t *get_surface(App *a, WallpaperItem *item, int w, int h) {
    char *key = g_strdup_printf("%s@%dx%d", item->path, w, h);
    CachedSurface *c = (CachedSurface *)g_hash_table_lookup(a->cache, key);
    if (c) {
        c->last_used = ++a->serial;
        g_free(key);
        return c->surface;
    }

    if (!g_hash_table_contains(a->pending, key)) {
        g_hash_table_add(a->pending, g_strdup(key));
        ThumbnailJob *j = g_new0(ThumbnailJob, 1);
        j->app = a;
        j->key = g_strdup(key);
        j->path = g_strdup(item->path);
        j->target_w = w;
        j->target_h = h;
        g_thread_pool_push(a->workers, j, NULL);
    }
    g_free(key);
    return NULL;
}

static gboolean on_animation_tick(GtkWidget *widget, GdkFrameClock *clock, gpointer data) {
    (void)clock;
    App *a = (App *)data;
    double diff = a->target_position - a->position;
    if (fabs(diff) > 0.001) {
        a->position += diff * 0.22;
        gtk_widget_queue_draw(widget);
        return G_SOURCE_CONTINUE;
    }
    a->position = a->target_position;
    a->tick_id = 0;
    gtk_widget_queue_draw(widget);
    return G_SOURCE_REMOVE;
}

static void trigger_animation(App *a) {
    if (!a->tick_id && a->drawing_area) {
        a->tick_id = gtk_widget_add_tick_callback(a->drawing_area, on_animation_tick, a, NULL);
    }
}

static void apply_current_wallpaper(App *a) {
    if (a->applying || !a->filtered->len) return;
    a->applying = TRUE;
    WallpaperItem *item = (WallpaperItem *)g_ptr_array_index(a->filtered, a->index);

    char *argv[] = {"zenith-native", "wallpaper", "apply", item->path, NULL};
    g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);

    g_idle_add((GSourceFunc)gtk_window_destroy, a->window);
}

static void filter_category(App *a) {
    g_ptr_array_set_size(a->filtered, 0);
    const char *target_cat = (const char *)g_ptr_array_index(a->categories, a->category_index);
    gboolean all = (strcmp(target_cat, "All") == 0);

    for (guint i = 0; i < a->items->len; i++) {
        WallpaperItem *item = (WallpaperItem *)g_ptr_array_index(a->items, i);
        if (all || strcmp(item->category, target_cat) == 0) {
            g_ptr_array_add(a->filtered, item);
        }
    }
    a->index = 0;
    a->position = 0;
    a->target_position = 0;
    if (a->drawing_area) gtk_widget_queue_draw(a->drawing_area);
}

static void on_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer data) {
    (void)area;
    App *a = (App *)data;

    // Translucent dark frosted glass background
    cairo_set_source_rgba(cr, 0.05, 0.07, 0.10, 0.88);
    cairo_paint(cr);

    if (!a->filtered->len) {
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.8);
        cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
        cairo_set_font_size(cr, 24);
        cairo_move_to(cr, width / 2.0 - 140, height / 2.0);
        cairo_show_text(cr, "No Wallpapers Found");
        return;
    }

    // =========================================================================
    // 1. TOP HERO PREVIEW VIEWPORT (65% Height)
    // =========================================================================
    double hero_h = height * 0.62;
    double hero_w = hero_h * (16.0 / 9.0);
    if (hero_w > width - 80) {
        hero_w = width - 80;
        hero_h = hero_w * (9.0 / 16.0);
    }
    double hero_x = (width - hero_w) / 2.0;
    double hero_y = 28.0;

    WallpaperItem *current = (WallpaperItem *)g_ptr_array_index(a->filtered, a->index);
    cairo_surface_t *hero_surf = get_surface(a, current, (int)hero_w, (int)hero_h);

    // Hero Drop Shadow
    draw_rounded_rect(cr, hero_x + 4, hero_y + 8, hero_w, hero_h, 18);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.55);
    cairo_fill(cr);

    // Hero Image Clip & Render
    cairo_save(cr);
    draw_rounded_rect(cr, hero_x, hero_y, hero_w, hero_h, 18);
    cairo_clip(cr);
    if (hero_surf) {
        cairo_translate(cr, hero_x, hero_y);
        cairo_scale(cr, hero_w / cairo_image_surface_get_width(hero_surf),
                        hero_h / cairo_image_surface_get_height(hero_surf));
        cairo_set_source_surface(cr, hero_surf, 0, 0);
        cairo_paint(cr);
    } else {
        cairo_set_source_rgba(cr, 0.12, 0.15, 0.22, 1.0);
        cairo_paint(cr);
    }
    cairo_restore(cr);

    // Hero 2px Accent Border
    draw_rounded_rect(cr, hero_x, hero_y, hero_w, hero_h, 18);
    cairo_set_source_rgba(cr, a->accent[0], a->accent[1], a->accent[2], 0.85);
    cairo_set_line_width(cr, 2.0);
    cairo_stroke(cr);

    // Hero Metadata Overlay Banner
    cairo_select_font_face(cr, "JetBrainsMono Nerd Font", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
    cairo_set_font_size(cr, 15);
    cairo_set_source_rgba(cr, 0.95, 0.96, 1.0, 0.95);
    cairo_move_to(cr, hero_x + 20, hero_y + hero_h - 22);
    cairo_show_text(cr, current->stem);

    // Category Pill Badge on Hero
    char cat_badge[64];
    snprintf(cat_badge, sizeof(cat_badge), " %s ", current->category);
    cairo_set_font_size(cr, 11);
    cairo_text_extents_t cat_ext;
    cairo_text_extents(cr, cat_badge, &cat_ext);
    draw_rounded_rect(cr, hero_x + hero_w - cat_ext.width - 32, hero_y + hero_h - 34, cat_ext.width + 16, 22, 8);
    cairo_set_source_rgba(cr, a->accent[0], a->accent[1], a->accent[2], 0.35);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.95);
    cairo_move_to(cr, hero_x + hero_w - cat_ext.width - 24, hero_y + hero_h - 18);
    cairo_show_text(cr, cat_badge);

    // =========================================================================
    // 2. BOTTOM HORIZONTAL FILMSTRIP DOCK (Bottom 30%)
    // =========================================================================
    double card_w = 230.0;
    double card_h = 130.0; // 16:9 Widescreen thumbnail
    double card_spacing = 22.0;
    double strip_y = hero_y + hero_h + 26.0;

    a->n_bounds = 0;
    int center_idx = (int)round(a->position);

    for (int offset = -5; offset <= 5; offset++) {
        int idx = center_idx + offset;
        if (idx < 0 || idx >= (int)a->filtered->len) continue;

        double rel = idx - a->position;
        double card_x = (width / 2.0) + (rel * (card_w + card_spacing)) - (card_w / 2.0);
        gboolean is_active = (idx == a->index);

        double render_w = is_active ? card_w * 1.05 : card_w;
        double render_h = is_active ? card_h * 1.05 : card_h;
        double render_x = card_x - (render_w - card_w) / 2.0;
        double render_y = strip_y - (render_h - card_h) / 2.0;

        if (a->n_bounds < 32) {
            a->bounds[a->n_bounds++] = (CardBounds){idx, render_x, render_y, render_w, render_h};
        }

        WallpaperItem *item = (WallpaperItem *)g_ptr_array_index(a->filtered, idx);
        cairo_surface_t *thumb = get_surface(a, item, (int)render_w, (int)render_h);

        // Thumbnail Card Shadow
        draw_rounded_rect(cr, render_x + 2, render_y + 4, render_w, render_h, 12);
        cairo_set_source_rgba(cr, 0, 0, 0, 0.45);
        cairo_fill(cr);

        // Thumbnail Card Image Clip & Render
        cairo_save(cr);
        draw_rounded_rect(cr, render_x, render_y, render_w, render_h, 12);
        cairo_clip(cr);
        if (thumb) {
            cairo_translate(cr, render_x, render_y);
            cairo_scale(cr, render_w / cairo_image_surface_get_width(thumb),
                            render_h / cairo_image_surface_get_height(thumb));
            cairo_set_source_surface(cr, thumb, 0, 0);
            cairo_paint(cr);
        } else {
            cairo_set_source_rgba(cr, 0.10, 0.13, 0.18, 1.0);
            cairo_paint(cr);
        }

        // Inactive Dimming Mask
        if (!is_active) {
            cairo_set_source_rgba(cr, 0, 0, 0, 0.45);
            cairo_paint(cr);
        }
        cairo_restore(cr);

        // Border Glow
        draw_rounded_rect(cr, render_x, render_y, render_w, render_h, 12);
        if (is_active) {
            cairo_set_source_rgba(cr, a->accent[0], a->accent[1], a->accent[2], 0.95);
            cairo_set_line_width(cr, 3.0);
        } else {
            cairo_set_source_rgba(cr, 0.35, 0.42, 0.55, 0.35);
            cairo_set_line_width(cr, 1.5);
        }
        cairo_stroke(cr);

        // Category Badge Chip on Top-Left of Card
        char badge_txt[32];
        snprintf(badge_txt, sizeof(badge_txt), "%s", item->category);
        cairo_set_font_size(cr, 9.5);
        cairo_text_extents_t b_ext;
        cairo_text_extents(cr, badge_txt, &b_ext);
        draw_rounded_rect(cr, render_x + 8, render_y + 8, b_ext.width + 12, 18, 6);
        cairo_set_source_rgba(cr, 0.08, 0.10, 0.15, 0.75);
        cairo_fill(cr);
        cairo_set_source_rgba(cr, 0.90, 0.92, 0.98, 0.95);
        cairo_move_to(cr, render_x + 14, render_y + 21);
        cairo_show_text(cr, badge_txt);
    }
}

static gboolean on_key_pressed(GtkEventControllerKey *c, guint keyval, guint code, GdkModifierType state, gpointer data) {
    (void)c; (void)code; (void)state;
    App *a = (App *)data;

    switch (keyval) {
        case GDK_KEY_Left:
        case GDK_KEY_h:
            if (a->index > 0) {
                a->index--;
                a->target_position = a->index;
                trigger_animation(a);
            }
            return TRUE;
        case GDK_KEY_Right:
        case GDK_KEY_l:
            if (a->index < (int)a->filtered->len - 1) {
                a->index++;
                a->target_position = a->index;
                trigger_animation(a);
            }
            return TRUE;
        case GDK_KEY_Tab:
            a->category_index = (a->category_index + 1) % a->categories->len;
            filter_category(a);
            return TRUE;
        case GDK_KEY_Return:
        case GDK_KEY_KP_Enter:
            apply_current_wallpaper(a);
            return TRUE;
        case GDK_KEY_Escape:
            gtk_window_destroy(GTK_WINDOW(a->window));
            return TRUE;
    }
    return FALSE;
}

static gboolean on_scroll(GtkEventControllerScroll *c, double dx, double dy, gpointer data) {
    (void)c; (void)dx;
    App *a = (App *)data;
    if (dy > 0 && a->index < (int)a->filtered->len - 1) {
        a->index++;
        a->target_position = a->index;
        trigger_animation(a);
    } else if (dy < 0 && a->index > 0) {
        a->index--;
        a->target_position = a->index;
        trigger_animation(a);
    }
    return TRUE;
}

static void on_click(GtkGestureClick *gesture, int n_press, double x, double y, gpointer data) {
    (void)gesture;
    App *a = (App *)data;
    for (int i = 0; i < a->n_bounds; i++) {
        CardBounds b = a->bounds[i];
        if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
            a->index = b.index;
            a->target_position = a->index;
            trigger_animation(a);
            if (n_press >= 2) apply_current_wallpaper(a);
            break;
        }
    }
}

static void discover_wallpapers(App *a) {
    const char *home = getenv("HOME");
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/.config/zenith/wallpapers", home ? home : "");

    DIR *d = opendir(path);
    if (!d) return;

    struct dirent *dir;
    GHashTable *seen_cats = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    g_ptr_array_add(a->categories, g_strdup("All"));

    while ((dir = readdir(d)) != NULL) {
        if (dir->d_name[0] == '.') continue;
        char cat_path[PATH_MAX];
        snprintf(cat_path, sizeof(cat_path), "%s/%s", path, dir->d_name);

        DIR *sub = opendir(cat_path);
        if (sub) {
            char *cat_name = g_strdup(dir->d_name);
            if (!g_hash_table_contains(seen_cats, cat_name)) {
                g_hash_table_add(seen_cats, g_strdup(cat_name));
                g_ptr_array_add(a->categories, g_strdup(cat_name));
            }

            struct dirent *sub_dir;
            while ((sub_dir = readdir(sub)) != NULL) {
                if (sub_dir->d_name[0] == '.') continue;
                char file_path[PATH_MAX];
                snprintf(file_path, sizeof(file_path), "%s/%s", cat_path, sub_dir->d_name);

                WallpaperItem *item = g_new0(WallpaperItem, 1);
                item->path = g_strdup(file_path);
                item->category = g_strdup(cat_name);
                item->stem = g_strdup(sub_dir->d_name);
                g_ptr_array_add(a->items, item);
                g_ptr_array_add(a->filtered, item);
            }
            closedir(sub);
            g_free(cat_name);
        }
    }
    closedir(d);
    g_hash_table_destroy(seen_cats);
}

static void on_activate(GtkApplication *app, gpointer data) {
    App *a = (App *)data;
    a->window = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(a->window), "Zenith Wallpaper Shower");
    gtk_window_set_default_size(GTK_WINDOW(a->window), 1280, 780);

    a->drawing_area = gtk_drawing_area_new();
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(a->drawing_area), on_draw, a, NULL);
    gtk_window_set_child(GTK_WINDOW(a->window), a->drawing_area);

    GtkEventController *key_ctrl = gtk_event_controller_key_new();
    g_signal_connect(key_ctrl, "key-pressed", G_CALLBACK(on_key_pressed), a);
    gtk_widget_add_controller(a->window, key_ctrl);

    GtkEventController *scroll_ctrl = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
    g_signal_connect(scroll_ctrl, "scroll", G_CALLBACK(on_scroll), a);
    gtk_widget_add_controller(a->drawing_area, scroll_ctrl);

    GtkGesture *click_gesture = gtk_gesture_click_new();
    g_signal_connect(click_gesture, "pressed", G_CALLBACK(on_click), a);
    gtk_widget_add_controller(a->drawing_area, GTK_EVENT_CONTROLLER(click_gesture));

    gtk_window_present(GTK_WINDOW(a->window));
}

int main(int argc, char **argv) {
    App *a = g_new0(App, 1);
    a->alive = TRUE;
    a->accent[0] = 0.65; a->accent[1] = 0.55; a->accent[2] = 0.95; // Default accent
    a->items = g_ptr_array_new();
    a->filtered = g_ptr_array_new();
    a->categories = g_ptr_array_new();
    a->cache = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, surface_cache_destroy);
    a->pending = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    a->workers = g_thread_pool_new(worker_thumbnail_job, NULL, 4, FALSE, NULL);

    discover_wallpapers(a);

    a->application = gtk_application_new("org.zenith.gallery", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(a->application, "activate", G_CALLBACK(on_activate), a);

    int status = g_application_run(G_APPLICATION(a->application), argc, argv);
    g_object_unref(a->application);
    return status;
}
