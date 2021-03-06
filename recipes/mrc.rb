#
# Cookbook Name:: xtreemfs
# Recipe:: mrc
#
# Copyright (C) 2013 cloudbau GmbH
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

include_recipe "xtreemfs::default"

package "xtreemfs-server" do
  action :upgrade
end

if node[:xtreemfs][:mrc][:uuid].nil?
  node.set[:xtreemfs][:mrc][:uuid] = `uuidgen`
end

dir_service_hosts = get_service_hosts('dir')

template "/etc/xos/xtreemfs/mrcconfig.properties" do
  source "mrcconfig.properties.erb"
  mode 0440
  owner node[:xtreemfs][:user]
  group node[:xtreemfs][:group]
  variables({
     :dir_service_hosts => dir_service_hosts,
     :uuid => node[:xtreemfs][:mrc][:uuid],
     :ip_address => node[:xtreemfs][:mrc][:bind_ip],
     :hostname => node[:xtreemfs][:use_hostnames] ? node[:fqdn] : nil,
     :listen_port => node[:xtreemfs][:mrc][:listen_port],
     :http_port => node[:xtreemfs][:mrc][:http_port],
     :debug_level => 6, # 6 is default
     :babudb_debug_level => 6,
     :replication => node[:xtreemfs][:mrc][:replication],
     :babudb_sync => node[:xtreemfs][:mrc][:replication] ? 'FDATASYNC' : 'ASYNC'
  })
  notifies :restart, 'service[xtreemfs-mrc]', :delayed
end

if node[:xtreemfs][:mrc][:replication]
  mrc_repl_participants = get_service_hosts('mrc')

  template '/etc/xos/xtreemfs/server-repl-plugin/mrc.properties' do
    source "repl.properties.erb"
    mode 0440
    owner node[:xtreemfs][:user]
    group node[:xtreemfs][:group]
    variables({
      :service => 'MRC',
      :repl_port => node[:xtreemfs][:mrc][:repl_port],
      :repl_participants => mrc_repl_participants,
      :babudb_repl_sync_n => (mrc_repl_participants.length/2.0).ceil # TODO do something cleverer here
    })
    notifies :restart, 'service[xtreemfs-mrc]', :immediately
  end
end

template "/etc/init/xtreemfs-mrc.conf" do
  source "upstart.conf.erb"
  variables({
    :descr => 'XtreemFS MRC service',
    :class => 'org.xtreemfs.mrc.MRC',
    :config => '/etc/xos/xtreemfs/mrcconfig.properties',
    :user => node[:xtreemfs][:user],
    :group => node[:xtreemfs][:group],
    :start_on => 'started xtreemfs-dir',
    :stop_on => 'deconfiguring-networking'
  })
end

link '/etc/init.d/xtreemfs-mrc' do
  to '/lib/init/upstart-job' 
end

link '/var/log/xtreemfs/mrc.log' do
  to '/var/log/upstart/xtreemfs-mrc.log'
end

service "xtreemfs-mrc" do
  provider Chef::Provider::Service::Upstart
  action [ :enable, :start ]
end

ruby_block "block_until_xtreemfs_mrc_is_up" do
  block do
    until IO.popen("netstat -lnt").entries.select { |entry|
        entry.split[3] =~ /:#{node[:xtreemfs][:mrc][:listen_port]}$/
      }.size == 1
      Chef::Log.debug "service[xtreemfs-mrc] not listening on port #{node[:xtreemfs][:mrc][:listen_port]}"
      sleep 1
    end
  end
  action :create
end

node.set[:xtreemfs][:mrc][:service] = true
#node.save
