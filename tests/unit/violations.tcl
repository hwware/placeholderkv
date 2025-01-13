# SORT which stores an integer encoded element into a list.
# Just for coverage, no news here.
start_server [list overrides [list save ""] ] {
    test {SORT adds integer field to list} {
        r set S1 asdf
        r set S2 123 ;# integer encoded
        assert_encoding "int" S2
        r sadd myset 1 2
        r mset D1 1 D2 2
        r sort myset by D* get S* store mylist
        r llen mylist
    } {2} {cluster:skip}
}
