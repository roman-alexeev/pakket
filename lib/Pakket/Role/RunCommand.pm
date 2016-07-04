package Pakket::Role::RunCommand;
# ABSTRACT: Role for running commands

use Moose::Role;
use Pakket::Log;
use System::Command;
use Path::Tiny qw< path >;

sub run_command {
    my ( $self, $dir, $sys_cmds, $extra_opts ) = @_;
    log_info { join ' ', @{$sys_cmds} };

    my %opt = (
        cwd => path($dir)->stringify,

        %{ $extra_opts || {} },

        # 'trace' => $ENV{SYSTEM_COMMAND_TRACE},
    );

    my $cmd = System::Command->new( @{$sys_cmds}, \%opt );

    $cmd->loop_on(
        stdout => sub {
            my $msg = shift;
            chomp $msg;
            log_debug { $msg };
            1;
        },

        stderr => sub {
            my $msg = shift;
            chomp $msg;
            log_notice { $msg };
            1;
        },
    );
}

no Moose::Role;

1;

__END__
