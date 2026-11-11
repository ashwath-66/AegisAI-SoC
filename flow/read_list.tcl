# Vivado helper: reads a flat file list (lines = paths, "+incdir+x" = include dir, "//" = comment)
proc read_filelist {lists} {
    set srcs {}; set incs {}
    foreach lf $lists {
        set fh [open $lf]; set data [read $fh]; close $fh
        foreach l [split $data "\n"] {
            set l [string trim $l]
            if {$l eq "" || [string match "//*" $l]} continue
            if {[string match "+incdir+*" $l]} { lappend incs [string range $l 8 end]; continue }
            if {[lsearch -exact $srcs $l] < 0} { lappend srcs $l }
        }
    }
    return [list $srcs [lsort -unique $incs]]
}
