implement Theme;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
include "draw.m";
	draw: Draw;

Iobuf: import bufio;

Theme: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
	loadtheme: fn(path: string): int;
	listthemes: fn(): array of string;
	getname: fn(): string;
};

# Default colors (fallback - matches libtk/colrs.c)
default_colors := array[17] of {
	"#000000FF",	# TkCforegnd (0)
	"#DDDDDDFF",	# TkCbackgnd (1)
	"#EEEEEEFF",	# TkCbackgndlght (2)
	"#C8C8C8FF",	# TkCbackgnddark (3)
	"#B03060FF",	# TkCselect (4)
	"#404040FF",	# TkCselectbgnd (5)
	"#505050FF",	# TkCselectbgndlght (6)
	"#303030FF",	# TkCselectbgnddark (7)
	"#FFFFFFFF",	# TkCselectfgnd (8)
	"#EDEDEDFF",	# TkCactivebgnd (9)
	"#FEFEFEFF",	# TkCactivebgndlght (10)
	"#D8D8D8FF",	# TkCactivebgnddark (11)
	"#000000FF",	# TkCactivefgnd (12)
	"#888888FF",	# TkCdisablefgnd (13)
	"#000000FF",	# TkChighlightfgnd (14)
	"#DDDDDDFF",	# TkCfill (15)
	"#00000000",	# TkCtransparent (16)
};

# Color names in order (index 0-16)
colornames := array[17] of {
	"foreground",
	"background",
	"background_light",
	"background_dark",
	"select",
	"select_background",
	"select_background_light",
	"select_background_dark",
	"select_foreground",
	"active_background",
	"active_background_light",
	"active_background_dark",
	"active_foreground",
	"disabled_foreground",
	"highlight_foreground",
	"fill",
	"transparent",
};

# Get color index by name
get_color_index(name: string): int
{
	for(i := 0; i < len colornames; i++) {
		if(colornames[i] == name)
			return i;
	}
	return -1;
}

current_theme: string = "default";

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	draw = load Draw Draw->PATH;

	if (argv == nil || len argv < 2) {
		sys->fprint(sys->fildes(2), "usage: theme load <file> | theme list | theme getname\n");
		return;
	}

	cmd := hd tl argv;

	case cmd {
	"load" =>
		if (len argv < 3) {
			sys->fprint(sys->fildes(2), "usage: theme load <file>\n");
			return;
		}
		r := loadtheme(hd tl tl argv);
		if (r != 0)
			sys->fprint(sys->fildes(2), "theme: failed to load: %r\n");
		else
			sys->fprint(sys->fildes(2), "theme: loaded %s\n", current_theme);

	"list" =>
		themes := listthemes();
		for (i := 0; i < len themes; i++)
			sys->print("%s\n", themes[i]);

	"getname" =>
		sys->print("%s\n", getname());

	* =>
		sys->fprint(sys->fildes(2), "theme: unknown command: %s\n", cmd);
	}
}

# Load theme from file
loadtheme(path: string): int
{
	if (path == nil)
		return -1;

	fd := sys->open(path, Sys->OREAD);
	if (fd == nil)
		return -1;

	io := bufio->fopen(fd, Sys->OREAD);
	if (io == nil)
		return -1;

	new_colors := array[17] of string;
	for (i := 0; i < 17; i++)
		new_colors[i] = default_colors[i];

	while ((line := io.gets('\n')) != nil) {
		line = line[0: len line - 1];

		if (len line == 0 || line[0] == '#')
			continue;

		eq := 0;
		for (i = 0; i < len line; i++) {
			if (line[i] == '=') {
				eq = i;
				break;
			}
		}

		if (eq == 0)
			continue;

		name := line[0:eq];
		color := line[eq + 1:];

		# Trim whitespace from name
		while (len name > 0 && name[0] == ' ')
			name = name[1:];
		while (len name > 0 && name[len name - 1] == ' ')
			name = name[0: len name - 1];

		# Trim whitespace from color
		while (len color > 0 && color[0] == ' ')
			color = color[1:];
		while (len color > 0 && color[len color - 1] == ' ')
			color = color[0: len color - 1];

		idx := get_color_index(name);
		if (idx >= 0) {
			if (len color >= 7 && color[0] == '#') {
				new_colors[idx] = color;
			}
		}
	}

	# Apply colors to theme device
	for (k := 0; k < 17; k++) {
		devpath := sys->sprint("#w/%d", k);
		cfd := sys->open(devpath, Sys->OWRITE);
		if (cfd != nil) {
			sys->write(cfd, array of byte new_colors[k], len new_colors[k]);
		}
	}

	# Extract theme name from path
	for (k = len path - 1; k >= 0; k--) {
		if (path[k] == '/') {
			current_theme = path[k+1:];
			# Strip .theme extension
			for (j := len current_theme - 1; j >= 0; j--) {
				if (current_theme[j] == '.') {
					current_theme = current_theme[0:j];
					break;
				}
			}
			break;
		}
	}

	return 0;
}

getname(): string
{
	return current_theme;
}

listthemes(): array of string
{
	fd := sys->open("/lib/theme", Sys->OREAD);
	if (fd == nil)
		return nil;

	themes: list of string = nil;

	for (;;) {
		(n, dirs) := sys->dirread(fd);
		if (n <= 0)
			break;

		for (j := 0; j < len dirs; j++) {
			d := dirs[j];
			if (len d.name >= 6 && d.name[len d.name - 6:] == ".theme")
				themes = d.name[0: len d.name - 6] :: themes;
		}
	}

	result := array[len themes] of string;
	i := len result - 1;
	for (; themes != nil; themes = tl themes) {
		result[i--] = hd themes;
	}

	return result;
}
