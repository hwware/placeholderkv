start_cluster 1 0 {tags {"expire external:skip cluster"}} {
    test "expire scan should skip dictionaries with lot's of empty buckets" {
        r debug set-active-expire 0

        # Collect two slots to help determine the expiry scan logic is able
        # to go past certain slots which aren't valid for scanning at the given point of time.
        # And the next non empty slot after that still gets scanned and expiration happens.

        # hashslot(alice) is 749
        r psetex alice 500 val

        # hashslot(foo) is 12182
        # fill data across different slots with expiration
        for {set j 1} {$j <= 1000} {incr j} {
            r psetex "{foo}$j" 500 a
        }
        # hashslot(key) is 12539
        r psetex key 500 val

        # disable resizing, the reason for not using slow bgsave is because
        # it will hit the dict_force_resize_ratio.
        r debug dict-resizing 0

        # delete data to have lot's (99%) of empty buckets (slot 12182 should be skipped)
        for {set j 1} {$j <= 999} {incr j} {
            r del "{foo}$j"
        }

        # Trigger a full traversal of all dictionaries.
        r keys *

        r debug set-active-expire 1

        # Verify {foo}100 still exists and remaining got cleaned up
        wait_for_condition 20 100 {
            [r dbsize] eq 1
        } else {
            if {[r dbsize] eq 0} {
                puts [r debug htstats 0]
                fail "scan didn't handle slot skipping logic."
            } else {
                puts [r debug htstats 0]
                fail "scan didn't process all valid slots."
            }
        }

        # Enable resizing
        r debug dict-resizing 1

        # put some data into slot 12182 and trigger the resize
        # by deleting it to trigger shrink
        r psetex "{foo}0" 500 a
        r del "{foo}0"

        # Verify all keys have expired
        wait_for_condition 400 100 {
            [r dbsize] eq 0
        } else {
            puts [r dbsize]
            flush stdout
            fail "Keys did not actively expire."
        }

        # Make sure we don't have any timeouts.
        assert_equal 0 [s 0 expired_time_cap_reached_count]
    } {} {needs:debug}
}
