use strict;
use warnings;
use English;
use Test::More;
use Test::Exception;
use File::Spec::Functions qw( catdir splitpath rel2abs );

#use OpenXPKI::Debug; $OpenXPKI::Debug::LEVEL{'OpenXPKI::Server::Database.*'} = 2;

#
# setup
#
my $basedir = catdir((splitpath(rel2abs(__FILE__)))[0,1]);
require "$basedir/DatabaseTest.pm";

my $db = DatabaseTest->new(
    columns => [ # yes an ArrayRef to have a defined order!
        id => "INTEGER PRIMARY KEY",
        text => "VARCHAR(100)",
        entropy => "INTEGER",
    ],
    data => [
        [ 1, "Litfasssaeule", 1 ],
        [ 2, "Buergersteig",  1 ],
        [ 3, "Rathaus",       42 ],
        [ 4, "Kindergarten",  3 ],
    ],
);

#
# tests
#
$db->run("SQL DELETE", 10, sub {
    my $t = shift;
    my $dbi = $t->dbi;

    # delete one existing row
    lives_ok {
        $dbi->delete(
            from => "test",
            where => [ -and => { text => "Rathaus" }, { entropy => 42 } ],
        );
        is_deeply $t->get_data, [
            [ 1, "Litfasssaeule", 1],
            [ 2, "Buergersteig",  1],
            [ 4, "Kindergarten",  3],
        ];
    } "delete one row";

    # delete two existing rows
    lives_ok {
        $dbi->delete(
            from => "test",
            where => { entropy => 1 },
        );
        is_deeply $t->get_data, [
            [ 4, "Kindergarten",  3],
        ];
    } "delete multiple rows";

    # prevent accidential deletion of all rows
    dies_ok {
        $dbi->delete(from => "test")
    } "prevent accidential deletion of all rows (no WHERE clause)";

    dies_ok {
        $dbi->delete(from => "test", where => "")
    } "prevent accidential deletion of all rows (empty WHERE string)";

    dies_ok {
        $dbi->delete(from => "test", where => {})
    } "prevent accidential deletion of all rows (empty WHERE hash)";

    dies_ok {
        $dbi->delete(from => "test", where => [])
    } "prevent accidential deletion of all rows (empty WHERE array)";

    lives_ok {
        $dbi->delete(from => "test", all => 1)
    } "allow intended deletion of all rows";

    is_deeply $t->get_data, [];
});

done_testing($db->test_no);