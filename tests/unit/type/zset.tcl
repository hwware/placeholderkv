start_server {tags {"zset"}} {
    proc create_zset {key items} {
        r del $key
        foreach {score entry} $items {
            r zadd $key $score $entry
        }
    }

    # A helper function to verify either ZPOP* or ZMPOP* response.
    proc verify_pop_response {pop res zpop_expected_response zmpop_expected_response} {
        if {[string match "*ZM*" $pop]} {
            assert_equal $res $zmpop_expected_response
        } else {
            assert_equal $res $zpop_expected_response
        }
    }

    # A helper function to verify either ZPOP* or ZMPOP* response when given one input key.
    proc verify_zpop_response {rd pop key count zpop_expected_response zmpop_expected_response} {
        if {[string match "ZM*" $pop]} {
            lassign [split $pop "_"] pop where

            if {$count == 0} {
                set res [$rd $pop 1 $key $where]
            } else {
                set res [$rd $pop 1 $key $where COUNT $count]
            }
        } else {
            if {$count == 0} {
                set res [$rd $pop $key]
            } else {
                set res [$rd $pop $key $count]
            }
        }
        verify_pop_response $pop $res $zpop_expected_response $zmpop_expected_response
    }

    # A helper function to verify either BZPOP* or BZMPOP* response when given one input key.
    proc verify_bzpop_response {rd pop key timeout count bzpop_expected_response bzmpop_expected_response} {
        if {[string match "BZM*" $pop]} {
            lassign [split $pop "_"] pop where

            if {$count == 0} {
                $rd $pop $timeout 1 $key $where
            } else {
                $rd $pop $timeout 1 $key $where COUNT $count
            }
        } else {
            $rd $pop $key $timeout
        }
        verify_pop_response $pop [$rd read] $bzpop_expected_response $bzmpop_expected_response
    }

    # A helper function to verify either ZPOP* or ZMPOP* response when given two input keys.
    proc verify_bzpop_two_key_response {rd pop key key2 timeout count bzpop_expected_response bzmpop_expected_response} {
        if {[string match "BZM*" $pop]} {
            lassign [split $pop "_"] pop where

            if {$count == 0} {
                $rd $pop $timeout 2 $key $key2 $where
            } else {
                $rd $pop $timeout 2 $key $key2 $where COUNT $count
            }
        } else {
            $rd $pop $key $key2 $timeout
        }
        verify_pop_response $pop [$rd read] $bzpop_expected_response $bzmpop_expected_response
    }

    # A helper function to execute either BZPOP* or BZMPOP* with one input key.
    proc bzpop_command {rd pop key timeout} {
        if {[string match "BZM*" $pop]} {
            lassign [split $pop "_"] pop where
            $rd $pop $timeout 1 $key $where COUNT 1
        } else {
            $rd $pop $key $timeout
        }
    }

    # A helper function to verify nil response in readraw base on RESP version.
    proc verify_nil_response {resp nil_response} {
        if {$resp == 2} {
            assert_equal $nil_response {*-1}
        } elseif {$resp == 3} {
            assert_equal $nil_response {_}
        }
    }

    # A helper function to verify zset score response in readraw base on RESP version.
    proc verify_score_response {rd resp score} {
        if {$resp == 2} {
            assert_equal [$rd read] {$1}
            assert_equal [$rd read] $score
        } elseif {$resp == 3} {
            assert_equal [$rd read] ",$score"
        }
    }

    proc basics {encoding} {
        set original_max_entries [lindex [r config get zset-max-ziplist-entries] 1]
        set original_max_value [lindex [r config get zset-max-ziplist-value] 1]
        if {$encoding == "listpack"} {
            r config set zset-max-ziplist-entries 128
            r config set zset-max-ziplist-value 64
        } elseif {$encoding == "skiplist"} {
            r config set zset-max-ziplist-entries 0
            r config set zset-max-ziplist-value 0
        } else {
            puts "Unknown sorted set encoding"
            exit
        }


        proc create_default_zset {} {
            create_zset zset {-inf a 1 b 2 c 3 d 4 e 5 f +inf g}
        }

        proc create_long_zset {key length} {
            r del $key
            for {set i 0} {$i < $length} {incr i 1} {
                r zadd $key $i i$i
            }
        }

        proc create_default_lex_zset {} {
            create_zset zset {0 alpha 0 bar 0 cool 0 down
                              0 elephant 0 foo 0 great 0 hill
                              0 omega}
        }

        proc create_long_lex_zset {} {
            create_zset zset {0 alpha 0 bar 0 cool 0 down
                              0 elephant 0 foo 0 great 0 hill
                              0 island 0 jacket 0 key 0 lip 
                              0 max 0 null 0 omega 0 point
                              0 query 0 result 0 sea 0 tree}
        }


        r config set zset-max-ziplist-entries $original_max_entries
        r config set zset-max-ziplist-value $original_max_value
    }

    basics listpack
    basics skiplist

    test "BZMPOP should not blocks on non key arguments - #10762" {
        set rd1 [valkey_deferring_client]
        set rd2 [valkey_deferring_client]
        r del myzset myzset2 myzset3

        $rd1 bzmpop 0 1 myzset min count 10
        wait_for_blocked_clients_count 1
        $rd2 bzmpop 0 2 myzset2 myzset3 max count 10
        wait_for_blocked_clients_count 2

        # These non-key keys will not unblock the clients.
        r zadd 0 100 timeout_value
        r zadd 1 200 numkeys_value
        r zadd min 300 min_token
        r zadd max 400 max_token
        r zadd count 500 count_token
        r zadd 10 600 count_value

        r zadd myzset 1 zset
        r zadd myzset3 1 zset3
        assert_equal {myzset {{zset 1}}} [$rd1 read]
        assert_equal {myzset3 {{zset3 1}}} [$rd2 read]

        $rd1 close
        $rd2 close
    } {0} {cluster:skip}

}
