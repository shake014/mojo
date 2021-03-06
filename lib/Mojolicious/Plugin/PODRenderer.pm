package Mojolicious::Plugin::PODRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Asset::File;
use Mojo::ByteStream 'b';
use Mojo::DOM;
use Mojo::Util 'url_escape';
use Pod::Simple::HTML;
use Pod::Simple::Search;

# Paths
my @PATHS = map { $_, "$_/pods" } @INC;

# "This is my first visit to the Galaxy of Terror and I'd like it to be a
#  pleasant one."
sub register {
  my ($self, $app, $conf) = @_;

  # Add "pod" handler
  my $preprocess = $conf->{preprocess} || 'ep';
  $app->renderer->add_handler(
    $conf->{name} || 'pod' => sub {
      my ($r, $c, $output, $options) = @_;

      # Preprocess and render
      return unless $r->handlers->{$preprocess}->($r, $c, $output, $options);
      $$output = _pod_to_html($$output);
      return 1;
    }
  );

  # Add "pod_to_html" helper
  $app->helper(pod_to_html => sub { shift; b(_pod_to_html(@_)) });

  # Perldoc
  return if $conf->{no_perldoc};
  return $app->routes->any(
    '/perldoc/*module' => {module => 'Mojolicious/Guides'} => \&_perldoc);
}

sub _perldoc {
  my $self = shift;

  # Find module
  my $module = $self->param('module');
  $module =~ s!/!\:\:!g;
  my $path = Pod::Simple::Search->new->find($module, @PATHS);

  # Redirect to CPAN
  return $self->redirect_to("http://metacpan.org/module/$module")
    unless $path && -r $path;

  # Turn POD into HTML
  open my $file, '<', $path;
  my $html = _pod_to_html(join '', <$file>);

  # Rewrite links
  my $dom     = Mojo::DOM->new("$html");
  my $perldoc = $self->url_for('/perldoc/');
  $dom->find('a[href]')->each(
    sub {
      my $attrs = shift->attrs;
      $attrs->{href} =~ s!%3A%3A!/!gi
        if $attrs->{href} =~ s!^http\://search\.cpan\.org/perldoc\?!$perldoc!;
    }
  );

  # Rewrite code blocks for syntax highlighting
  $dom->find('pre')->each(
    sub {
      my $e = shift;
      return if $e->all_text =~ /^\s*\$\s+/m;
      my $attrs = $e->attrs;
      my $class = $attrs->{class};
      $attrs->{class} = defined $class ? "$class prettyprint" : 'prettyprint';
    }
  );

  # Rewrite headers
  my $url = $self->req->url->clone;
  my (%anchors, @parts);
  $dom->find('h1, h2, h3')->each(
    sub {
      my $e = shift;

      # Anchor and text
      my $name = my $text = $e->all_text;
      $name =~ s/\s+/_/g;
      $name =~ s/\W//g;
      my $anchor = $name;
      my $i      = 1;
      $anchor = $name . $i++ while $anchors{$anchor}++;

      # Rewrite
      push @parts, [] if $e->type eq 'h1' || !@parts;
      push @{$parts[-1]}, $text, $url->fragment($anchor)->to_abs;
      $e->replace_content(
        $self->link_to(
          $text => $url->fragment('toc')->to_abs,
          class => 'mojoscroll',
          id    => $anchor
        )
      );
    }
  );

  # Try to find a title
  my $title = 'Perldoc';
  $dom->find('h1 + p')->first(sub { $title = shift->text });

  # Combine everything to a proper response
  $self->content_for(perldoc => "$dom");
  my $template = $self->app->renderer->_bundled('perldoc');
  $self->render(inline => $template, title => $title, parts => \@parts);
  $self->res->headers->content_type('text/html;charset="UTF-8"');
}

# "Aw, he looks like a little insane drunken angel."
sub _pod_to_html {
  return unless defined(my $pod = shift);

  # Block
  $pod = $pod->() if ref $pod eq 'CODE';

  # Parser
  my $parser = Pod::Simple::HTML->new;
  $parser->force_title('');
  $parser->html_header_before_title('');
  $parser->html_header_after_title('');
  $parser->html_footer('');

  # Parse
  $parser->output_string(\(my $output));
  return $@ unless eval { $parser->parse_string_document("$pod"); 1 };

  # Filter
  $output =~ s!<a name='___top' class='dummyTopAnchor'\s*?></a>\n!!g;
  $output =~ s!<a class='u'.*?name=".*?"\s*>(.*?)</a>!$1!sg;

  return $output;
}

1;

=head1 NAME

Mojolicious::Plugin::PODRenderer - POD renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  my $route = $self->plugin('PODRenderer');
  my $route = $self->plugin(PODRenderer => {name => 'foo'});
  my $route = $self->plugin(PODRenderer => {preprocess => 'epl'});

  # Mojolicious::Lite
  my $route = plugin 'PODRenderer';
  my $route = plugin PODRenderer => {name => 'foo'};
  my $route = plugin PODRenderer => {preprocess => 'epl'};

  # foo.html.ep
  %= pod_to_html "=head1 TEST\n\nC<123>"

=head1 DESCRIPTION

L<Mojolicious::Plugin::PODRenderer> is a renderer for true Perl hackers, rawr!

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

=head1 OPTIONS

L<Mojolicious::Plugin::PODRenderer> supports the following options.

=head2 C<name>

  # Mojolicious::Lite
  plugin PODRenderer => {name => 'foo'};

Handler name.

=head2 C<no_perldoc>

  # Mojolicious::Lite
  plugin PODRenderer => {no_perldoc => 1};

Disable perldoc browser.

=head2 C<preprocess>

  # Mojolicious::Lite
  plugin PODRenderer => {preprocess => 'epl'};

Name of handler used to preprocess POD.

=head1 HELPERS

L<Mojolicious::Plugin::PODRenderer> implements the following helpers.

=head2 C<pod_to_html>

  %= pod_to_html '=head2 lalala'
  <%= pod_to_html begin %>=head2 lalala<% end %>

Render POD to HTML without preprocessing.

=head1 METHODS

L<Mojolicious::Plugin::PODRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  my $route = $plugin->register(Mojolicious->new);
  my $route = $plugin->register(Mojolicious->new, {name => 'foo'});

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
