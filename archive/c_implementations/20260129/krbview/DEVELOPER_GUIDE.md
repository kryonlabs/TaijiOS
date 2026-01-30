# krbview Developer Quick Reference

## Quick Start

```bash
# Build
cd /mnt/storage/Projects/TaijiOS
mk install

# Run tests
./tests/krbview/run_tests.sh

# View a file
./utils/krbview/krbview examples/hello-world.krb
```

## Project Structure

```
utils/krbview/
├── *.c              # Implementation files (1135 lines total)
├── *.h              # Header files
├── mkfile           # Build configuration
└── Documentation
```

## Key Components

### 1. Main Application (krbview.c)
**Entry Point:** `main()`

**Flow:**
```
init → run → cleanup
```

**Key Data Structure:**
```c
typedef struct {
    Display *display;
    Image *window;
    KrbFile *krb_file;
    KrbRuntime *runtime;
    KrbDrawContext *draw_ctx;
    void *rc_vm;
    // ... event state
} KrbviewApp;
```

### 2. Loader (krbview_loader.c)
**Purpose:** Load and validate KRB files

**API:**
```c
KrbFile* krbview_loader_load(const char *path);
int krbview_loader_validate(KrbFile *file);
void krbview_loader_free(KrbFile *file);
```

### 3. Renderer (krbview_renderer.c)
**Purpose:** Render KRB content to window

**API:**
```c
KrbDrawContext* krbview_renderer_init(...);
void krbview_renderer_render(KrbDrawContext *ctx, KrbWidget *root);
void krbview_renderer_clear(KrbDrawContext *ctx, uint32_t color);
```

### 4. Events (krbview_events.c)
**Purpose:** Handle mouse/keyboard input

**API:**
```c
int krbview_events_init(...);
int krbview_events_read(...);
int krbview_events_process(KrbRuntime *runtime, KrbviewEvent *event);
KrbWidget* krbview_events_hit_test(KrbRuntime *runtime, Point pos);
```

### 5. RC Integration (krbview_rc.c)
**Purpose:** Execute RC scripts in KRB files

**API:**
```c
KrbviewRCVM* krbview_rc_init(KrbRuntime *runtime);
int krbview_rc_execute_script(KrbviewRCVM *vm, const char *name);
void krbview_rc_export_widget_vars(KrbviewRCVM *vm, KrbWidget *w);
void krbview_rc_import_widget_vars(KrbviewRCVM *vm, KrbWidget *w);
```

## Event Flow

```
User Action (click/key)
    ↓
krbview_events_read()
    ↓
krbview_events_process()
    ↓
krbview_events_hit_test() → Find widget
    ↓
krbview_events_trigger()
    ↓
krb_runtime_trigger_event()
    ↓
krb_shell_execute_function()
    ↓
krbview_rc_export_widget_vars() → Set $widget_id, etc.
    ↓
Execute RC code
    ↓
krbview_rc_import_widget_vars() → Get changed vars
    ↓
Update widget state
    ↓
krbview_redraw()
```

## RC Script Variables

### Automatic (set before execution)
- `$widget_id` - ID of widget that triggered event
- `$widget_type` - Type name (e.g., "Button")
- `$event_type` - Event name (e.g., "click")
- `$mouse_x`, `$mouse_y` - Mouse position
- `$key` - Keyboard input

### Built-in Functions
```rc
# Get widget property
get_widget_prop <widget_id> <property>

# Set widget property
set_widget_prop <widget_id> <property> <value>

# Print to status bar
echo <message>
```

## Adding a New Widget Type

### 1. Add Renderer (in libkrb_render.a)
```c
void krb_render_mywidget(KrbDrawContext *ctx, KrbWidget *widget) {
    // Render implementation
}
```

### 2. Register in Widget Factory
```c
// In runtime.c or widget_factory.c
case KRB_WIDGET_TYPE_MYWIDGET:
    return create_mywidget(instance);
```

### 3. Add Test Case
```kry
// tests/krbview/mywidget_test.kry
MyWidget {
    id = "test_mywidget"
    property = "value"
}
```

## Debugging

### Enable Debug Mode
```bash
krbview -debug -rc-debug file.krb
```

### Common Issues

**Issue:** "Failed to load KRB file"
- Check file path
- Verify KRB is valid: `kryon decompile file.krb`
- Check file permissions

**Issue:** "RC shell integration failed"
- Warning only - app continues without RC
- Check libkrb_shell.a is built
- Verify Inferno sh.dis is available

**Issue:** Window doesn't appear
- Check DISPLAY is set
- Verify X11/Wayland is running
- Check libdraw initialization

## Performance Tips

1. **Reduce Redraws**
   - Only call `krbview_redraw()` when state changes
   - Use dirty region tracking (TODO)

2. **Optimize Layout**
   - Avoid deeply nested containers
   - Use fixed sizes where possible
   - Cache layout calculations

3. **Minimize RC Execution**
   - Keep scripts short
   - Avoid file I/O in event handlers
   - Cache computed values

## Testing

### Unit Test Structure
```c
void test_krbview_loader() {
    KrbFile *file = krbview_loader_load("test.krb");
    assert(file != NULL);
    assert(krbview_loader_validate(file));
    krbview_loader_free(file);
}
```

### Integration Test
```bash
# Compile test file
kryon compile test.kry -o test.krb

# Run with timeout
timeout 5 krbview test.krb
```

## Build System

### mkfile Variables
```makefile
TARG=krbview              # Executable name
OFILES=*.o                # Object files
LIBS=krb_render krb_runtime ...  # Libraries to link
BIN=$ROOT/$OBJDIR/bin     # Install location
```

### Dependencies
```
krbview → libkrb_render.a → libdraw.a
         → libkrb_runtime.a → libkrb.a
         → libkrb_shell.a
         → libmemdraw.a
```

## API Reference

### Public API (/include/krbview.h)
```c
// Create viewer
KrbviewApp* krbview_create(const char *krb_path, int w, int h);

// Run event loop
int krbview_run(KrbviewApp *app);

// Cleanup
void krbview_free(KrbviewApp *app);

// Convenience
int krbview_view_file(const char *krb_path);
```

### Internal APIs
See respective header files for detailed documentation:
- `krbview_loader.h` - File loading
- `krbview_renderer.h` - Rendering
- `krbview_events.h` - Event handling
- `krbview_rc.h` - RC integration

## Code Style

- **Indentation:** Tabs (Plan 9/Inferno convention)
- **Line length:** Prefer < 80 characters
- **Naming:** `snake_case` for functions, `PascalCase` for types
- **Comments:** C89 `/* */` style
- **Error handling:** Return NULL/-1 on error, set global error string

## Contributing

### Adding Features
1. Update IMPLEMENTATION_SUMMARY.md
2. Add test case to tests/krbview/
3. Update this guide
4. Run `./verify.sh`

### Submitting Patches
- Follow existing code style
- Test on Linux and Plan 9 if possible
- Document changes in commit message

## Resources

- **Main README:** utils/krbview/README
- **Implementation:** utils/krbview/IMPLEMENTATION_SUMMARY.md
- **Testing:** tests/krbview/TESTING.md
- **KRB Format:** include/krb.h
- **Runtime API:** include/krb_runtime.h
- **Renderer API:** include/krb_render.h

## Status

✅ Phase 1-3 Complete
🔜 Phase 4-5 Planned

**Current version:** 0.1.0
**Last updated:** 2025-01-29
