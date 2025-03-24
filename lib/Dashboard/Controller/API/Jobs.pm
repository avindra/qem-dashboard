# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Dashboard::Controller::API::Jobs;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub add ($self) {
  return $self->render(json => {error => 'Job in JSON format required'}, status => 400)
    unless my $job = $self->req->json;

  my $jv = $self->schema(
    {
      type     => 'object',
      required => ['name', 'job_group', 'job_id', 'group_id', 'status', 'distri', 'flavor', 'version', 'arch', 'build'],
      properties => {
        incident_settings => {anyOf => [{type => 'integer', minimum => 1}, {type => 'null'}]},
        update_settings   => {anyOf => [{type => 'integer', minimum => 1}, {type => 'null'}]},
        name              => {type => 'string'},
        job_group         => {type => 'string'},
        job_id            => {type => 'integer', minimum => 1},
        group_id          => {type => 'integer', minimum => 1},
        status            => {type => 'string',  enum    => ['unknown', 'waiting', 'passed', 'failed', 'stopped']},
        distri            => {type => 'string'},
        flavor            => {type => 'string'},
        version           => {type => 'string'},
        arch              => {type => 'string'},
        build             => {type => 'string'}
      }
    }
  );
  my @errors = $jv->validate($job);
  return $self->render(json => {error => "Job does not match the JSON schema: @errors"}, status => 400) if @errors;

  my $is_id = $job->{incident_settings};
  my $us_id = $job->{update_settings};
  return $self->render(json => {error => "Job needs to reference incident settings or update settings"}, status => 400)
    unless $is_id || $us_id;

  # Validate references to catch user errors
  if ($is_id) {
    return $self->render(json => {error => "Referenced incident settings ($is_id) do not exist"}, status => 400)
      unless $self->settings->incident_settings_exist($is_id);
  }
  if ($us_id) {
    return $self->render(json => {error => "Referenced update settings ($us_id) do not exist"}, status => 400)
      unless $self->settings->update_settings_exist($us_id);
  }

  $self->jobs->add($job);
  $self->render(json => {message => 'Ok'});
}

sub incidents ($self) {
  my $job = $self->jobs->get_incident_settings($self->param('incident_settings'));
  $self->render(json => $job);
}

sub modify ($self) {
  my $job_id = $self->param('job_id');

  return $self->render(json => {error => 'Job in JSON format required'}, status => 400)
    unless my $job_data = $self->req->json;

  my $jv     = $self->schema({type => 'object', properties => {obsolete => {type => 'boolean'}}});
  my @errors = $jv->validate($job_data);
  return $self->render(json => {error => "Job does not match the JSON schema: @errors"}, status => 400) if @errors;

  $self->jobs->modify($job_id, $job_data);
  $self->render(json => {message => 'Ok'});
}

sub _incident ($incidents, $remark) {
  return undef unless my $incident_id = $remark->{incident_id};
  return $incidents->number_for_id($incident_id);
}

sub show_remarks ($self) {
  my $openqa_job_id   = $self->param('job_id');
  my $internal_job_id = $self->jobs->internal_job_id($openqa_job_id);
  return $self->render(json => {error => "openQA job ($openqa_job_id) does not exist"}, status => 404)
    unless $internal_job_id;

  my $incidents = $self->app->incidents;
  my $remarks   = $self->jobs->remarks($internal_job_id);
  my $res       = {remarks => [map { {text => $_->{text}, incident => _incident($incidents, $_)} } $remarks->each]};
  $self->render(json => $res);
}

sub update_remark ($self) {
  my $incident_number = $self->param('incident_number');
  my $incident_id     = defined $incident_number ? $self->app->incidents->id_for_number($incident_number) : undef;
  my $openqa_job_id   = $self->param('job_id');
  my $internal_job_id = $self->jobs->internal_job_id($openqa_job_id);
  return $self->render(json => {error => "openQA job ($openqa_job_id) does not exist"}, status => 404)
    unless $internal_job_id;
  return $self->render(json => {error => "Incident ($incident_number) does not exist"}, status => 404)
    if defined $incident_number && !$incident_id;

  $self->jobs->add_remark($internal_job_id, $incident_id, $self->param('text'));
  $self->render(json => {message => 'Ok'});
}

sub show ($self) {
  return $self->render(json => {error => 'Job not found'}, status => 400)
    unless my $job = $self->jobs->get($self->param('job_id'));
  $self->render(json => $job);
}

sub updates ($self) {
  my $job = $self->jobs->get_update_settings($self->param('update_settings'));
  $self->render(json => $job);
}

1;
