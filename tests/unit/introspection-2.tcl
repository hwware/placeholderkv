proc cmdstat {cmd} {
    return [cmdrstat $cmd r]
}

proc getlru {key} {
    set objinfo [r debug object $key]
    foreach info $objinfo {
        set kvinfo [split $info ":"]
        if {[string compare [lindex $kvinfo 0] "lru"] == 0} {
            return [lindex $kvinfo 1]
        }
    }
    fail "Can't get LRU info with DEBUG OBJECT"
}

start_server {tags {"introspection"}} {

    test "COMMAND LIST FILTERBY PATTERN - list all commands/subcommands" {
        # Exact command match.
        assert_equal {set} [r command list filterby pattern set]
        assert_equal {get} [r command list filterby pattern get]

        # Return the parent command and all the subcommands below it.
        set commands [r command list filterby pattern config*]
        assert_not_equal [lsearch $commands "config"] -1
        assert_not_equal [lsearch $commands "config|get"] -1

        # We can filter subcommands under a parent command.
        set commands [r command list filterby pattern config|*re*]
        assert_not_equal [lsearch $commands "config|resetstat"] -1
        assert_not_equal [lsearch $commands "config|rewrite"] -1

        # We can filter subcommands across parent commands.
        set commands [r command list filterby pattern cl*help]
        assert_not_equal [lsearch $commands "client|help"] -1
        assert_not_equal [lsearch $commands "cluster|help"] -1

        # Negative check, command that doesn't exist.
        assert_equal {} [r command list filterby pattern non_exists]
        assert_equal {} [r command list filterby pattern non_exists*]
    }

}
