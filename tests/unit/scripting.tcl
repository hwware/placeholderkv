foreach is_eval {0 1} {
foreach script_compatibility_api {server redis} {

# We run the tests using both the server APIs, e.g. server.call(), and valkey APIs, e.g. redis.call(),
# in order to ensure compatibility.
if {$script_compatibility_api eq "server"} {
    proc replace_script_redis_api_with_server {args} {
        set new_string [regsub -all {redis\.} [lindex $args 0] {server.}]
        return lreplace $args 0 0 $new_string
    }

    proc get_script_api_name {} {
        return "server"
    }
} else {
    proc replace_script_redis_api_with_server {args} {
        return {*}$args
    }

    proc get_script_api_name {} {
        return "redis"
    }
}

if {$is_eval == 1} {
    proc run_script {args} {
        set args [replace_script_redis_api_with_server $args]
        r eval {*}$args
    }
    proc run_script_ro {args} {
        set args [replace_script_redis_api_with_server $args]
        r eval_ro {*}$args
    }
    proc run_script_on_connection {args} {
        set args [replace_script_redis_api_with_server $args]
        [lindex $args 0] eval {*}[lrange $args 1 end]
    }
    proc kill_script {args} {
        r script kill
    }
} else {
    proc run_script {args} {
        set args [replace_script_redis_api_with_server $args]
        r function load replace [format "#!lua name=test\n%s.register_function('test', function(KEYS, ARGV)\n %s \nend)" [get_script_api_name] [lindex $args 0]]
        if {[r readingraw] eq 1} {
            # read name
            assert_equal {test} [r read]
        }
        r fcall test {*}[lrange $args 1 end]
    }
    proc run_script_ro {args} {
        set args [replace_script_redis_api_with_server $args]
        r function load replace [format "#!lua name=test\n%s.register_function{function_name='test', callback=function(KEYS, ARGV)\n %s \nend, flags={'no-writes'}}" [get_script_api_name] [lindex $args 0]]
        if {[r readingraw] eq 1} {
            # read name
            assert_equal {test} [r read]
        }
        r fcall_ro test {*}[lrange $args 1 end]
    }
    proc run_script_on_connection {args} {
        set args [replace_script_redis_api_with_server $args]
        set rd [lindex $args 0]
        $rd function load replace [format "#!lua name=test\n%s.register_function('test', function(KEYS, ARGV)\n %s \nend)" [get_script_api_name] [lindex $args 1]]
        # read name
        $rd read
        $rd fcall test {*}[lrange $args 2 end]
    }
    proc kill_script {args} {
        r function kill
    }
}

start_server {tags {"scripting"}} {


    if {$is_eval eq 1 && $script_compatibility_api == "redis"} {
    # script command is only relevant for is_eval Lua
    test "SORT is normally not alpha re-ordered for the scripting engine" {
        r del myset
        r sadd myset 1 2 3 4 10
        r eval {return redis.call('sort',KEYS[1],'desc')} 1 myset
    } {10 4 3 2 1} {cluster:skip}

    test "SORT BY <constant> output gets ordered for scripting" {
        r del myset
        r sadd myset a b c d e f g h i l m n o p q r s t u v z aa aaa azz
        r eval {return redis.call('sort',KEYS[1],'by','_')} 1 myset
    } {a aa aaa azz b c d e f g h i l m n o p q r s t u v z} {cluster:skip}

    test "SORT BY <constant> with GET gets ordered for scripting" {
        r del myset
        r sadd myset a b c
        r eval {return redis.call('sort',KEYS[1],'by','_','get','#','get','_:*')} 1 myset
    } {a {} b {} c {}} {cluster:skip}
    } ;# is_eval


    if {$is_eval eq 1 && $script_compatibility_api == "redis"} {
    test {SPOP: We can call scripts rewriting client->argv from Lua} {
        set repl [attach_to_replication_stream]
        #this sadd operation is for external-cluster test. If myset doesn't exist, 'del myset' won't get propagated.
        r sadd myset ppp
        r del myset
        r sadd myset a b c
        assert {[r eval {return redis.call('spop', 'myset')} 0] ne {}}
        assert {[r eval {return redis.call('spop', 'myset', 1)} 0] ne {}}
        assert {[r eval {return redis.call('spop', KEYS[1])} 1 myset] ne {}}
        # this one below should not be replicated
        assert {[r eval {return redis.call('spop', KEYS[1])} 1 myset] eq {}}
        r set trailingkey 1
        assert_replication_stream $repl {
            {select *}
            {sadd *}
            {del *}
            {sadd *}
            {srem myset *}
            {srem myset *}
            {srem myset *}
            {set *}
        }
        close_replication_stream $repl
    } {} {needs:repl}


    } ;# is_eval

    test {CLUSTER RESET can not be invoke from within a script} {
        catch {
            run_script {
                  redis.call('cluster', 'reset', 'hard')
            } 0
        } e
        set _ $e
    } {*command is not allowed*}

}

} ;# foreach is_eval
} ;# foreach script_compatibility_api

# Additional eval only tests
start_server {tags {"scripting"}} {
    test "Consistent eval error reporting" {
        r config resetstat
        r config set maxmemory 1
        # Script aborted due to server state (OOM) should report script execution error with detailed internal error
        assert_error {OOM command not allowed when used memory > 'maxmemory'*} {
            r eval {return redis.call('set','x','y')} 1 x
        }
        assert_equal [errorrstat OOM r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=0*rejected_calls=1,failed_calls=0*} [cmdrstat set r]
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat eval r]

        # redis.pcall() failure due to server state (OOM) returns lua error table with server error message without '-' prefix
        r config resetstat
        assert_equal [
            r eval {
                local t = redis.pcall('set','x','y')
                if t['err'] == "OOM command not allowed when used memory > 'maxmemory'." then
                    return 1
                else
                    return 0
                end
            } 1 x
        ] 1
        # error stats were not incremented
        assert_equal [errorrstat ERR r] {}
        assert_equal [errorrstat OOM r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=0*rejected_calls=1,failed_calls=0*} [cmdrstat set r]
        assert_match {calls=1*rejected_calls=0,failed_calls=0*} [cmdrstat eval r]
        
        # Returning an error object from lua is handled as a valid RESP error result.
        r config resetstat
        assert_error {OOM command not allowed when used memory > 'maxmemory'.} {
            r eval { return redis.pcall('set','x','y') } 1 x
        }
        assert_equal [errorrstat ERR r] {}
        assert_equal [errorrstat OOM r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=0*rejected_calls=1,failed_calls=0*} [cmdrstat set r]
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat eval r]

        r config set maxmemory 0
        r config resetstat
        # Script aborted due to error result of server command
        assert_error {ERR DB index is out of range*} {
            r eval {return redis.call('select',99)} 0
        }
        assert_equal [errorrstat ERR r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat select r]
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat eval r]
        
        # redis.pcall() failure due to error in server command returns lua error table with server error message without '-' prefix
        r config resetstat
        assert_equal [
            r eval {
                local t = redis.pcall('select',99)
                if t['err'] == "ERR DB index is out of range" then
                    return 1
                else
                    return 0
                end
            } 0
        ] 1
        assert_equal [errorrstat ERR r] {count=1} ;
        assert_equal [s total_error_replies] {1}
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat select r]
        assert_match {calls=1*rejected_calls=0,failed_calls=0*} [cmdrstat eval r]

        # Script aborted due to scripting specific error state (write cmd with eval_ro) should report script execution error with detailed internal error
        r config resetstat
        assert_error {ERR Write commands are not allowed from read-only scripts*} {
            r eval_ro {return redis.call('set','x','y')} 1 x
        }
        assert_equal [errorrstat ERR r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=0*rejected_calls=1,failed_calls=0*} [cmdrstat set r]
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat eval_ro r]

        # redis.pcall() failure due to scripting specific error state (write cmd with eval_ro) returns lua error table with server error message without '-' prefix
        r config resetstat
        assert_equal [
            r eval_ro {
                local t = redis.pcall('set','x','y')
                if t['err'] == "ERR Write commands are not allowed from read-only scripts." then
                    return 1
                else
                    return 0
                end
            } 1 x
        ] 1
        assert_equal [errorrstat ERR r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=0*rejected_calls=1,failed_calls=0*} [cmdrstat set r]
        assert_match {calls=1*rejected_calls=0,failed_calls=0*} [cmdrstat eval_ro r]

        r config resetstat
        # make sure geoadd will failed
        r set Sicily 1
        assert_error {WRONGTYPE Operation against a key holding the wrong kind of value*} {
            r eval {return redis.call('GEOADD', 'Sicily', '13.361389', '38.115556', 'Palermo', '15.087269', '37.502669', 'Catania')} 1 x
        }
        assert_equal [errorrstat WRONGTYPE r] {count=1}
        assert_equal [s total_error_replies] {1}
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat geoadd r]
        assert_match {calls=1*rejected_calls=0,failed_calls=1*} [cmdrstat eval r]
    } {} {cluster:skip}
}
