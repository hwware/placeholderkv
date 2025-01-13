proc wait_for_dbsize {size} {
    set r2 [valkey_client]
    wait_for_condition 50 100 {
        [$r2 dbsize] == $size
    } else {
        fail "Target dbsize not reached"
    }
    $r2 close
}

start_server {tags {"multi"}} {

    test {EXEC fail on WATCHed key modified by SORT with STORE even if the result is empty} {
        r flushdb
        r lpush foo bar
        r watch foo
        r sort emptylist store foo
        r multi
        r ping
        r exec
    } {} {cluster:skip}

    test {MULTI / EXEC with REPLICAOF} {
        # This test verifies that if we demote a master to replica inside a transaction, the
        # entire transaction is not propagated to the already-connected replica
        set repl [attach_to_replication_stream]
        r set foo bar
        r multi
        r set foo2 bar
        r replicaof localhost 9999
        r set foo3 bar
        r exec
        catch {r set foo4 bar} e
        assert_match {READONLY*} $e
        assert_replication_stream $repl {
            {select *}
            {set foo bar}
        }
        r replicaof no one
    } {OK} {needs:repl cluster:skip}

    test {exec with read commands and stale replica state change} {
        # check that exec that contains read commands fails if server state changed since they were queued
        r config set replica-serve-stale-data no
        set r1 [valkey_client]
        r set xx 1

        # check that GET and PING are disallowed on stale replica, even if the replica becomes stale only after queuing.
        r multi
        r get xx
        $r1 replicaof localhsot 0
        catch {r exec} e
        assert_match {*EXECABORT*MASTERDOWN*} $e

        # reset
        $r1 replicaof no one

        r multi
        r ping
        $r1 replicaof localhsot 0
        catch {r exec} e
        assert_match {*EXECABORT*MASTERDOWN*} $e

        # check that when replica is not stale, GET is allowed
        # while we're at it, let's check that multi is allowed on stale replica too
        r multi
        $r1 replicaof no one
        r get xx
        set xx [r exec]
        # make sure that the INCR was executed
        assert { $xx == 1 }
        $r1 close
    } {0} {needs:repl cluster:skip}

    test {MULTI propagation of PUBLISH} {
        set repl [attach_to_replication_stream]

        r multi
        r publish bla bla
        r exec

        assert_replication_stream $repl {
            {select *}
            {publish bla bla}
        }
        close_replication_stream $repl
    } {} {needs:repl cluster:skip}

}

start_cluster 1 0 {tags {"external:skip cluster"}} {
    test "Regression test for multi-exec with RANDOMKEY accessing the wrong per-slot dictionary" {
        R 0 SETEX FOO 10000 BAR
        R 0 SETEX FIZZ 10000 BUZZ

        R 0 MULTI
        R 0 DEL FOO
        R 0 RANDOMKEY
        assert_equal [R 0 EXEC] {1 FIZZ}
    }
}
