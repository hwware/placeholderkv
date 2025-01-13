start_server {tags {"keyspace"}} {

    test {Untagged multi-key commands} {
        r mset foo1 a foo2 b foo3 c
        assert_equal {a b c {}} [r mget foo1 foo2 foo3 foo4]
        r del foo1 foo2 foo3 foo4
    } {3} {cluster:skip}
}

start_cluster 1 0 {tags {"keyspace external:skip cluster"}} {
    test {KEYS with empty DB in cluster mode} {
        assert_equal {} [r keys *]
        assert_equal {} [r keys foo*]
    }

    test {KEYS with empty slot in cluster mode} {
        assert_equal {} [r keys foo]
    }
}
