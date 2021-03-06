package PlSense::ModuleKeeper;

use parent qw{ PlSense::Cacheable };
use strict;
use warnings;
use Class::Std;
use List::AllUtils qw{ uniq };
use Try::Tiny;
use PlSense::Logger;
{
    my %cache_of :ATTR( :default(undef) );
    my %projcache_of :ATTR( :default(undef) );
    my %moduleh_of :ATTR();

    sub START {
        my ($class, $ident, $arg_ref) = @_;
        $cache_of{$ident} = $class->new_cache('Module');
        $projcache_of{$ident} = $class->new_cache('Module.'.$class->get_default_project_name);
        $moduleh_of{$ident} = {};
    }

    sub set_project {
        my ($self, $projectnm) = @_;
        $self->SUPER::set_project($projectnm) or return;
        my $nextns = "Module.".$projectnm;
        $projcache_of{ident $self}->set_namespace($nextns);
    }

    sub switch_project {
        my ($self, $projectnm) = @_;

        if ( ! $projectnm ) { return; }
        if ( $projectnm eq $self->get_project() ) {
            logger->info("No need switch project data from [$projectnm]");
            return;
        }

        logger->info("Switch project data to [$projectnm]");
        $self->set_project($projectnm);
        MDL:
        foreach my $mdlkey ( keys %{$moduleh_of{ident $self}} ) {
            my $mdl = $moduleh_of{ident $self}->{$mdlkey};
            if ( ! $mdl->get_projectnm ) { next MDL; }
            delete $moduleh_of{ident $self}->{$mdlkey};
        }
        return 1;
    }

    sub store_module {
        my ($self, $mdl) = @_;
        $self->store_module_sentinel($mdl);
        return;
    }

    sub load_module {
        my $self = shift;
        my $mdlnm = shift || "";
        my $filepath = shift || "";
        my $key = $self->get_cache_key($mdlnm, $filepath);
        return $self->load_module_sentinel($key);
    }

    sub remove_module {
        my $self = shift;
        my $mdlnm = shift || "";
        my $filepath = shift || "";
        my $projectnm = shift || "";
        my $key = $self->get_cache_key($mdlnm, $filepath);
        delete $moduleh_of{ident $self}->{$key};
        if ( $projectnm ) {
            try   { $projcache_of{ident $self}->remove($key); }
            catch { $projcache_of{ident $self}->remove($key); };
        }
        else {
            try   { $cache_of{ident $self}->remove($key); }
            catch { $cache_of{ident $self}->remove($key); };
        }
        logger->info("Removed module info of [$mdlnm] in [$filepath]");
    }

    sub remove_project_all_module {
        my ($self) = @_;
        MDL:
        foreach my $mdlkey ( keys %{$moduleh_of{ident $self}} ) {
            my $mdl = $moduleh_of{ident $self}->{$mdlkey};
            if ( ! $mdl->get_projectnm ) { next MDL; }
            delete $moduleh_of{ident $self}->{$mdlkey};
        }
        try   { $projcache_of{ident $self}->clear; }
        catch { $projcache_of{ident $self}->clear; };
        logger->info("Removed all project module info of [".$projcache_of{ident $self}->get_namespace."]");
    }

    sub remove_all_module {
        my ($self) = @_;
        $self->reset;
        try   { $cache_of{ident $self}->clear; }
        catch { $cache_of{ident $self}->clear; };
        try   { $projcache_of{ident $self}->clear; }
        catch { $projcache_of{ident $self}->clear; };
        logger->info("Removed all module info");
    }

    sub reset {
        my $self = shift;
        $moduleh_of{ident $self} = {};
    }

    sub get_module {
        my $self = shift;
        my $mdlnm = shift || "";
        my $filepath = shift || "";
        my $key = $self->get_cache_key($mdlnm, $filepath);
        return $moduleh_of{ident $self}->{$key} || $self->load_module($mdlnm, $filepath);
    }

    sub get_module_with_best_effort {
        my $self = shift;
        my $mdlnm = shift || "";
        my $filepath = shift || "";
        my $key = $self->get_cache_key($mdlnm, $filepath);
        my $mdl = $moduleh_of{ident $self}->{$key};
        return $mdl && $mdl->is_initialized ? $mdl : $self->load_module($mdlnm, $filepath);
    }

    sub get_bundle_modules {
        my ($self, $filepath) = @_;
        my @ret = ();

        if ( ! -f $filepath ) {
            logger->error("Not exist file [$filepath]");
            return @ret;
        }

        my $mainmdl = $self->get_module("main", $filepath) or return @ret;
        push @ret, $mainmdl;
        for my $i ( 1..$mainmdl->count_bundlemdl ) { push @ret, $mainmdl->get_bundlemdl($i); }
        return @ret;
    }

    sub get_packages {
        my ($self) = @_;
        return sort { $a->get_name cmp $b->get_name } grep { $_->get_name ne "main" } values %{$moduleh_of{ident $self}};
    }

    sub get_built_modules {
        my ($self) = @_;
        return grep { $_->is_initialized } $self->get_packages;
    }

    sub describe_keep_value {
        my ($self) = @_;
        my @mdlkeys = keys %{$moduleh_of{ident $self}};
        return "Modules ... ".($#mdlkeys+1)."\n";
    }


    sub store_module_sentinel : PRIVATE {
        my ($self, $mdl) = @_;
        if ( ! $mdl || ! $mdl->isa("PlSense::Symbol::Module") ) { return; }

        my $key = $self->get_cache_key($mdl->get_name, $mdl->get_filepath);
        if ( ! $moduleh_of{ident $self}->{$key} ) {
            $moduleh_of{ident $self}->{$key} = $mdl;
        }

        my (@parents, @usingmdls, @bundlemdls);
        PARENT:
        for my $i ( 1..$mdl->count_parent ) {
            my $parent = $mdl->get_parent($i);
            push @parents, $parent->renew;
        }
        USINGMODULE:
        for my $i ( 1..$mdl->count_usingmdl ) {
            my $usingmdl = $mdl->get_usingmdl($i);
            push @usingmdls, $usingmdl->renew;
        }
        BUNDLEMODULE:
        for my $i ( 1..$mdl->count_bundlemdl ) {
            my $bundlemdl = $mdl->get_bundlemdl($i);
            push @bundlemdls, $bundlemdl->renew;
        }

        $mdl->reset_parent;
        $mdl->reset_usingmdl;
        $mdl->reset_bundlemdl;

        PARENT:
        foreach my $parent ( @parents ) { $mdl->push_parent($parent); }
        USINGMODULE:
        foreach my $usingmdl ( @usingmdls ) { $mdl->push_usingmdl($usingmdl); }
        BUNDLEMODULE:
        foreach my $bundlemdl ( @bundlemdls ) { $mdl->push_bundlemdl($bundlemdl); }

        if ( ! $mdl->get_projectnm ) {
            try   { $cache_of{ident $self}->set($key, $mdl); }
            catch { $cache_of{ident $self}->set($key, $mdl); };
        }
        elsif ( $projcache_of{ident $self} ) {
            try   { $projcache_of{ident $self}->set($key, $mdl); }
            catch { $projcache_of{ident $self}->set($key, $mdl); };
        }
        logger->debug("Store module : $key");
        return;
    }

    sub load_module_sentinel : PRIVATE {
        my $self = shift;
        my $key = shift || "";
        my $mdl = $moduleh_of{ident $self}->{$key};

        my $cachemdl;
        try {
            if ( $projcache_of{ident $self} ) { $cachemdl = $projcache_of{ident $self}->get($key); }
            if ( ! $cachemdl                ) { $cachemdl = $cache_of{ident $self}->get($key); }
        } catch {
        };
        if ( ! $cachemdl || ! $cachemdl->isa("PlSense::Symbol::Module") ) { return; }

        if ( $mdl ) {
            $mdl->interchange_to($cachemdl);
            # logger->debug("Interchanged [".$mdl->get_name."] in [".$mdl->get_filepath."] belong [".$mdl->get_projectnm."]");
        }
        else {
            $moduleh_of{ident $self}->{$key} = $cachemdl;
            $mdl = $cachemdl;
            # logger->debug("Loaded [".$mdl->get_name."] in [".$mdl->get_filepath."] belong [".$mdl->get_projectnm."]");
        }

        my (@parents, @usingmdls, @bundlemdls);
        PARENT:
        for my $i ( 1..$mdl->count_parent ) {
            my $parent = $mdl->get_parent($i);
            my $validmdl = $self->get_module($parent->get_name);
            push @parents, $validmdl;
        }
        USINGMODULE:
        for my $i ( 1..$mdl->count_usingmdl ) {
            my $usingmdl = $mdl->get_usingmdl($i);
            my $validmdl = $self->get_module($usingmdl->get_name);
            push @usingmdls, $validmdl;
        }
        BUNDLEMODULE:
        for my $i ( 1..$mdl->count_bundlemdl ) {
            my $bundlemdl = $mdl->get_bundlemdl($i);
            my $validmdl = $self->get_module($bundlemdl->get_name);
            push @bundlemdls, $validmdl;
        }

        $mdl->reset_parent;
        $mdl->reset_usingmdl;
        $mdl->reset_bundlemdl;

        PARENT:
        foreach my $parent ( @parents ) { $mdl->push_parent($parent); }
        USINGMODULE:
        foreach my $usingmdl ( @usingmdls ) { $mdl->push_usingmdl($usingmdl); }
        BUNDLEMODULE:
        foreach my $bundlemdl ( @bundlemdls ) { $mdl->push_bundlemdl($bundlemdl); }

        return $mdl;
    }
}

1;

__END__
