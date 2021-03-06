require 'minitest/autorun'
require_relative '../../lib/ruby-manta'

class TestMantaClient < Minitest::Test
  @@client = nil
  @@user   = nil

  def setup
    if ! @@client
      host   = ENV['MANTA_URL']
      key    = ENV['MANTA_KEY' ]
      @@user = ENV['MANTA_USER']

      unless host && key && @@user
        $stderr.puts 'Require MANTA_URL, MANTA_USER and MANTA_KEY env variables to run tests.'
        $stderr.puts 'E.g. MANTA_USER=john MANTA_KEY=~/.ssh/john MANTA_URL=https://us-east.manta.joyent.com bundle exec rake test'
        exit
      end

      priv_key_data = File.read(key)

      opts = {
          disable_ssl_verification: true
      }

      if ENV.key?('MANTA_SUBUSER')
        opts[:subuser] = ENV['MANTA_SUBUSER']
      end

      @@client = RubyManta::MantaClient.new(host, @@user, priv_key_data, opts)

      @@test_dir_path = '/%s/stor/ruby-manta-test' % @@user
    end

    teardown()

    @@client.put_directory(@@test_dir_path)
  end



  def teardown
    listing, _ = @@client.list_directory(@@test_dir_path)
    listing.each do |entry, _|
      path = @@test_dir_path + '/' + entry['name']
      if entry['type'] == 'directory'
        @@client.delete_directory(path)
      else
        @@client.delete_object(path)
      end
    end

    @@client.delete_directory(@@test_dir_path)
  rescue RubyManta::MantaClient::ResourceNotFound
  end



  def test_paths
    def check(&blk)
      begin
        yield blk
        assert false
      rescue ArgumentError
      end
    end

    good_obj_path = "/#{@@user}/stor/ruby-manta-test"
    bad_obj_path  = "/#{@@user}/stora/ruby-manta-test"

    check { @@client.put_directory(bad_obj_path)            }
    check { @@client.put_object(bad_obj_path, 'asd')        }
    check { @@client.get_object(bad_obj_path)               }
    check { @@client.delete_object(bad_obj_path)            }
    check { @@client.put_directory(bad_obj_path)            }
    check { @@client.list_directory(bad_obj_path)           }
    check { @@client.delete_directory(bad_obj_path)         }
    check { @@client.put_snaplink(good_obj_path, bad_obj_path)  }
    check { @@client.put_snaplink(bad_obj_path,  good_obj_path) }

    good_job_path = "/#{@@user}/job/ruby-manta-test"
    bad_job_path  = "/#{@@user}/joba/ruby-manta-test"

    check { @@client.get_job(bad_job_path)                  }
    check { @@client.get_job_errors(bad_job_path)           }
    check { @@client.cancel_job(bad_job_path)               }
    check { @@client.add_job_keys(bad_job_path,  [good_obj_path]) }
    check { @@client.add_job_keys(good_job_path, [bad_obj_path])  }
    check { @@client.end_job_input(bad_job_path)            }
    check { @@client.get_job_input(bad_job_path)            }
    check { @@client.get_job_output(bad_job_path)           }
    check { @@client.get_job_failures(bad_job_path)         }
    check { @@client.gen_signed_url(Time.now, :get, bad_obj_path) }
  end



  def test_directories
    result, headers = @@client.put_directory(@@test_dir_path)
    assert_equal true, result
    assert headers.is_a? Hash

    result, headers = @@client.put_directory(@@test_dir_path + '/dir1')
    assert_equal true, result
    assert headers.is_a? Hash

    # since idempotent
    result, headers = @@client.put_directory(@@test_dir_path + '/dir1')
    assert_equal true, result
    assert headers.is_a? Hash

    result, headers = @@client.put_object(@@test_dir_path + '/obj1', 'obj1-data')
    assert_equal true, result
    assert headers.is_a? Hash

    result, headers = @@client.put_object(@@test_dir_path + '/obj2', 'obj2-data')
    assert_equal true, result
    assert headers.is_a? Hash

    result, headers = @@client.list_directory(@@test_dir_path)
    assert headers.is_a? Hash
    assert_equal 3, result.size

    assert_equal 'dir1', result[0]['name']
    assert_equal 'directory', result[0]['type']
    assert result[0]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/)

    assert_equal 'obj1', result[1]['name']
    assert_equal 'object', result[1]['type']
    assert_equal 9, result[1]['size']
    assert result[1]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/)

    assert_equal 'obj2', result[2]['name']
    assert_equal 'object', result[2]['type']
    assert_equal 9, result[2]['size']
    assert result[2]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/)

    result, _ = @@client.list_directory(@@test_dir_path, :limit => 2)
    assert_equal 2, result.size
    assert_equal 'dir1', result[0]['name']
    assert_equal 'obj1', result[1]['name']

    result, _ = @@client.list_directory(@@test_dir_path, :limit => 1)
    assert_equal 1, result.size
    assert_equal 'dir1', result[0]['name']

    result, _ = @@client.list_directory(@@test_dir_path, :limit  => 2,
                                                       :marker => 'obj1')
    assert_equal result.size, 2
    assert_equal 'obj1', result[0]['name']
    assert_equal 'obj2', result[1]['name']

    result, headers = @@client.list_directory(@@test_dir_path, :head => true)
    assert_equal true,  result
    assert_equal '3', headers['Result-Set-Size']

    begin
      @@client.delete_directory(@@test_dir_path)
      assert false
    rescue RubyManta::MantaClient::DirectoryNotEmpty
    end

    @@client.delete_directory(@@test_dir_path + '/dir1')
    @@client.delete_object(@@test_dir_path + '/obj1')
    @@client.delete_object(@@test_dir_path + '/obj2')

    result, headers = @@client.delete_directory(@@test_dir_path)
    assert_equal result, true
    assert headers.is_a? Hash

    begin
      @@client.list_directory(@@test_dir_path + '/does-not-exist')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.put_directory(@@test_dir_path + '/dir1')
      assert false
    rescue RubyManta::MantaClient::DirectoryDoesNotExist
    end
  end



  def test_root_directory
    if ENV['MANTA_SUBUSER']
      skip("Subusers can't get access to the root directory")
    end

    result, headers = @@client.list_directory('/' + @@user)
    assert headers.is_a? Hash
    assert_equal result.size, 4
    assert_equal result.map { |r| r['name'] }.sort, ['jobs', 'public', 'reports', 'stor']
  end



  def test_objects
    result, headers = @@client.put_object(@@test_dir_path + '/obj1', 'foo-data')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'foo-data'
    assert_equal headers['Content-Type'], 'application/x-www-form-urlencoded'

    @@client.put_object(@@test_dir_path + '/obj1', 'bar-data',
                        :content_type     => 'application/wacky',
                        :durability_level => 3)

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'bar-data'
    assert_equal headers['Content-Type'], 'application/wacky'

    result, headers = @@client.get_object(@@test_dir_path + '/obj1', :head => true)
    assert_equal result, true
    assert_equal headers['Content-Type'], 'application/wacky'

    begin
      @@client.put_object(@@test_dir_path + '/obj1', 'bar-data',
                          :durability_level => 999)
      assert false
    rescue RubyManta::MantaClient::InvalidDurabilityLevel
    end

    begin
      @@client.get_object(@@test_dir_path + '/does-not-exist')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.delete_object(@@test_dir_path + '/does-not-exist')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    result, headers = @@client.delete_object(@@test_dir_path + '/obj1')
    assert_equal result, true
    assert headers.is_a? Hash
  end



  def test_public
    fail 'MANTA_URL must be specified' unless ENV['MANTA_URL']

    host = ENV['MANTA_URL'].gsub('https', 'http')
    test_pub_dir_path  = '/%s/public/ruby-manta-test' % @@user

    @@client.put_directory(test_pub_dir_path)
    @@client.put_object(test_pub_dir_path + '/obj1', 'foo-data')

    client = HTTPClient.new
    client.ssl_config.verify_mode = nil  # temp hack
    result = client.get(host + test_pub_dir_path + '/obj1')
    assert_equal result.body, 'foo-data'

    @@client.delete_object(test_pub_dir_path + '/obj1')
    @@client.delete_directory(test_pub_dir_path)
  end



  def test_cors
    cors_args = {
      :access_control_allow_credentials => true,
      :access_control_allow_headers     => 'X-Random, X-Bar',
      :access_control_allow_methods     => 'GET, POST, DELETE',
      :access_control_allow_origin      => 'https://example.com:1234 http://127.0.0.1',
      :access_control_expose_headers    => 'X-Last-Read, X-Foo',
      :access_control_max_age           => 30
    }

    @@client.put_object(@@test_dir_path + '/obj1', 'foo-data', cors_args)

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'foo-data'

    for name, value in [[ 'access-control-allow-methods',     'GET, POST, DELETE'  ],
                        [ 'access-control-allow-origin',      'https://example.com:1234 http://127.0.0.1' ],
                        [ 'access-control-expose-headers',    'x-foo, x-last-read' ],
                        [ 'access-control-max-age',           '30'                 ] ]
      assert_equal headers[name], value
    end

    result, headers = @@client.get_object(@@test_dir_path + '/obj1',
                                          :origin => 'https://example.com:1234')

    assert_equal result, 'foo-data'

    for name, value in [[ 'access-control-allow-methods',     'GET, POST, DELETE'  ],
                        [ 'access-control-allow-origin',      nil                  ],
                        [ 'access-control-expose-headers',    'x-foo, x-last-read' ],
                        [ 'access-control-max-age',           nil                  ]]
      assert_equal headers[name], value
    end

    @@client.put_directory(@@test_dir_path + '/dir', cors_args)

    result, headers = @@client.list_directory(@@test_dir_path + '/dir')

    for name, value in [[ 'access-control-allow-methods',     'GET, POST, DELETE'  ],
                        [ 'access-control-allow-origin',      'https://example.com:1234 http://127.0.0.1' ],
                        [ 'access-control-expose-headers',    'x-foo, x-last-read' ],
                        [ 'access-control-max-age',           '30'                 ] ]
      assert_equal headers[name], value
    end
  end



  def test_signed_urls

    client = HTTPClient.new

    put_url = @@client.gen_signed_url(Time.now + 500000, [:put, :options],
                                      @@test_dir_path + '/obj1')

    # Subusers can't PUT to this path
    result = client.options("https://" + put_url, {
      'Access-Control-Request-Headers' => 'access-control-allow-origin, accept, content-type',
      'Access-Control-Request-Method' => 'PUT'
    })

    assert_equal 200, result.status, "Signed URL Failed: #{result.dump}"

    result = client.put("https://" + put_url, 'foo-data', { 'Content-Type' => 'text/plain' })
    assert_equal 204, result.status

    url = @@client.gen_signed_url(Time.now + 500000, :get,
                                  @@test_dir_path + '/obj1')

    result = client.get('http://' + url)
    assert_equal result.body, 'foo-data'
  end

  def test_snaplink_not_found
    begin
      @@client.put_snaplink(@@test_dir_path + '/obj1',
                            @@test_dir_path + '/obj2')
      assert false
    rescue RubyManta::MantaClient::SourceObjectNotFound
    end
  end

  def test_snaplinks
    @@client.put_object(@@test_dir_path + '/obj1', 'foo-data')

    result, headers = @@client.put_snaplink(@@test_dir_path + '/obj1',
                                            @@test_dir_path + '/obj2')
    assert_equal result, true
    assert headers.is_a? Hash

    @@client.put_object(@@test_dir_path + '/obj1', 'bar-data')

    result, _ = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'bar-data'

    result, _ = @@client.get_object(@@test_dir_path + '/obj2')
    assert_equal result, 'foo-data'
  end



  def test_referencing_invalid_reports_dir
    begin
      @@client.list_directory('/%s/reportse' % @@user)
      assert fail
    rescue ArgumentError
      assert true
    end
  end



  def test_reports
    result, headers = @@client.list_directory('/%s/reports' % @@user)
    assert headers.is_a? Hash
    assert result.is_a? Array

    if result.length < 1
      skip 'Usage directory has not been created yet'
    end

    begin
      result, headers = @@client.list_directory('/%s/reports/usage' % @@user)
    rescue => e
      if ENV.key?('MANTA_SUBUSER') &&
          e.message.include?('None of your active roles are present on the resource')
        skip("Subusers typically don't have access to the reports directory")
      end
    end

    assert headers.is_a? Hash
    assert result.is_a? Array
    assert result.length > 0
  end



  def test_conditionals_on_objects
    result, headers = @@client.put_object(@@test_dir_path + '/obj1', 'foo-data',
                                          :if_modified_since => Time.now)
    assert_equal result, true

    modified = headers['Last-Modified']
    assert modified

    sleep 1

    begin
      @@client.put_object(@@test_dir_path + '/obj1', 'bar-data',
                          :if_modified_since => modified)
      assert fail
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'foo-data'
    assert_equal headers['Last-Modified'], modified

    @@client.put_object(@@test_dir_path + '/obj1', 'bar-data',
                        :if_unmodified_since => modified)

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'bar-data'
    assert headers['Last-Modified'] != modified

    etag = headers['Etag']

    begin
      @@client.put_object(@@test_dir_path + '/obj1', 'foo-data',
                          :if_none_match => etag)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'bar-data'
    assert_equal headers['Etag'], etag

    @@client.put_object(@@test_dir_path + '/obj1', 'foo-data',
                        :if_match => etag)

    result, headers = @@client.get_object(@@test_dir_path + '/obj1')
    assert_equal result, 'foo-data'
    assert headers['Etag'] != etag

    begin
      @@client.get_object(@@test_dir_path + '/obj1', :if_match => etag)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    etag     = headers['Etag']
    modified = headers['Last-Modified']

    result, headers = @@client.get_object(@@test_dir_path + '/obj1',
                                          :if_match => etag)
    assert_equal result, 'foo-data'
    assert_equal headers['Etag'], etag

    result, headers = @@client.get_object(@@test_dir_path + '/obj1',
                                          :if_none_match => etag)
    assert_equal result, nil
    assert_equal headers['Etag'], etag

    result, headers = @@client.get_object(@@test_dir_path + '/obj1',
                                          :if_none_match => 'blahblah')
    assert_equal result, 'foo-data'
    assert_equal headers['Etag'], etag

    begin
      @@client.put_snaplink(@@test_dir_path + '/obj1',
                            @@test_dir_path + '/obj2',
                            :if_none_match => etag)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    result, headers = @@client.put_snaplink(@@test_dir_path + '/obj1',
                                            @@test_dir_path + '/obj2',
                                            :if_match => etag)
    assert true
    assert_equal headers['Etag'], etag

    begin
      @@client.put_snaplink(@@test_dir_path + '/obj1',
                            @@test_dir_path + '/obj3',
                            :if_modified_since => modified)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    @@client.put_snaplink(@@test_dir_path + '/obj1', @@test_dir_path + '/obj3',
                          :if_unmodified_since => modified)

    result, headers = @@client.put_snaplink(@@test_dir_path + '/obj1',
                                            @@test_dir_path + '/obj4',
                                            :if_unmodified_since => modified)
    assert true

    modified = headers['Last Modified']

    begin
      @@client.delete_object(@@test_dir_path + '/obj1', :if_none_match => etag)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    result, _ = @@client.delete_object(@@test_dir_path + '/obj1', :if_match => etag)
    assert_equal result, true

    sleep 1

    begin
      @@client.delete_object(@@test_dir_path + '/obj3', :if_unmodified_since => Time.now - 10000)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    begin
      @@client.delete_object(@@test_dir_path + '/obj3', :if_modified_since => Time.now)
      assert false
    rescue RubyManta::MantaClient::PreconditionFailed
    end

    @@client.delete_object(@@test_dir_path + '/obj3', :if_unmodified_since => Time.now)
    @@client.delete_object(@@test_dir_path + '/obj4', :if_modified_since=> Time.now - 10000)


    for obj_name in ['/obj1', '/obj3', '/obj4']
      begin
        @@client.get_object(@@test_dir_path + obj_name)
        assert false
      rescue RubyManta::MantaClient::ResourceNotFound
      end
    end
  end



  # This test is definitely not pretty, but splitting it up will make it
  # take much longer due to the redundant creation of jobs. Perhaps that's
  # the wrong choice...
  def test_jobs
    result, headers = @@client.list_jobs(:running)
    assert headers.is_a? Hash

    result.each do |entry|
      path = '/%s/jobs/%s' % [ @@user, entry['name'] ]

      begin
        @@client.cancel_job(path)
      rescue => e
        warn("Unable to cancel jobs: #{e.message}")
      end
    end

    begin
      @@client.create_job({})
      assert false
    rescue ArgumentError
    end

    result, headers = @@client.list_jobs(:running)

    unless result.empty?
      skip "We can't run a test job if we have jobs running because it becomes " +
           'a difficult coordination problem.'
    end

    assert headers.is_a? Hash

    path, headers  = @@client.create_job({ :phases => [{ :exec => 'grep foo' }] })
    assert path =~ Regexp.new('^/' + @@user + '/jobs/.+')
    assert headers.is_a? Hash

    result, headers  = @@client.cancel_job(path)
    assert_equal result, true
    assert headers.is_a? Hash

    path, _ = @@client.create_job({ :phases => [{ :exec => 'grep foo' }] })

    result, _ = @@client.list_jobs(:all)
    result.each do |job|
      assert job['name' ] =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      assert job['mtime'] =~ /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d\d\dZ$/
      assert_equal job['type'], 'directory'
    end

    assert result.size >= 1

    begin
      @@client.list_jobs(:some)
      assert false
    rescue ArgumentError
    end

    jobs, _ = @@client.list_jobs(:running)
    assert_equal jobs.size, 1
    assert_equal jobs[0]['type'], 'directory'
    assert_equal jobs[0]['name'], path.split('/').last

# Commented out until HEAD here by Manta
#    jobs, headers = @@client.list_jobs(:running, :head => true)
#    assert_equal jobs, true
#    assert_equal headers['Result-Set-Size'], 1

    job, headers = @@client.get_job(path)
    assert headers.is_a? Hash
    assert job['name'       ].is_a? String
    assert job['phases'     ].is_a? Array
    assert job['timeCreated'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d\d\dZ$/)
    assert_equal job['id'       ], path.split('/').last
    assert_equal job['state'    ], 'running'
    assert_equal job['cancelled'], false
    assert_equal job['timeDone' ], nil

    @@client.put_object(@@test_dir_path + '/obj1', 'foo-data')
    @@client.put_object(@@test_dir_path + '/obj2', 'bar-data')

    obj_key_paths = [@@test_dir_path + '/obj1',
                     @@test_dir_path + '/obj2',
                     @@test_dir_path + '/obj3']

    result, headers = @@client.add_job_keys(path, obj_key_paths)
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @@client.get_job_input(path)
    assert_equal result.sort, obj_key_paths.sort
    assert headers.is_a? Hash

    begin
      @@client.get_job_input(path + 'a')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.get_job_output(path + 'a')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.get_job_failures(path + 'a')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.get_job_errors(path + 'a')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    begin
      @@client.end_job_input(path + 'a')
      assert false
    rescue RubyManta::MantaClient::ResourceNotFound
    end

    result, headers = @@client.end_job_input(path)
    assert_equal result, true
    assert headers.is_a? Hash

    for i in (1...10)
      job, _ = @@client.get_job(path)
      break if job['state'] == 'done'
      sleep 1
    end

    result, headers = @@client.get_job_output(path)
    assert headers.is_a? Hash

    result, _ = @@client.get_object(result.first)
    assert_equal result, "foo-data\n"

    result, headers = @@client.get_job_failures(path)
    assert_equal result.sort, obj_key_paths.slice(1, 2).sort
    assert headers.is_a? Hash

    result, headers = @@client.get_job_errors(path)
    assert_equal result.size, 2
    assert headers.is_a? Hash

    obj2_result, obj3_result = result.sort { |i,j| i['input'] <=> j['input'] }

    assert obj2_result['what']
    assert obj2_result['stderr']
    assert_equal obj2_result['code'   ], 'UserTaskError'
    assert_equal obj2_result['message'], 'user command exited with code 1'
    assert_equal obj2_result['input'  ], obj_key_paths[1]
    assert_equal obj2_result['phase'  ], '0'

    assert obj3_result['what']
    assert obj2_result['stderr']
    assert_equal obj3_result['code'   ], 'ResourceNotFoundError'
    assert obj3_result['message'] =~ /^no such object/
    assert_equal obj3_result['input'  ], obj_key_paths[2]
    assert_equal obj3_result['phase'  ], '0'

    begin
      @@client.cancel_job(path)
      assert fail
    rescue RubyManta::MantaClient::InvalidJobState
    end
  end

  def test_find
    copies = 15

    begin
      copies.times do |i|
        @@client.put_object(@@test_dir_path + "/find_object_#{i}", 'test_find')
      end

      results = @@client.find(@@test_dir_path)

      assert_equal copies, results.length

      copies.times do |i|
        assert results.include? @@test_dir_path + "/find_object_#{i}"
      end
    ensure
      copies.times do |i|
        result, headers = @@client.delete_object(@@test_dir_path + "/find_object_#{i}")
        assert_equal result, true
        assert headers.is_a? Hash
      end
    end
  end

  def test_find_regex
    copies = 15

    begin
      copies.times do |i|
        @@client.put_object(@@test_dir_path + "/find_object_#{i}", 'test_find_regex')
      end

      @@client.put_object(@@test_dir_path + '/dog_biscuit', 'dont match me')

      results = @@client.find(@@test_dir_path, regex: 'find_object_.*')

      assert_equal copies, results.length

      copies.times do |i|
        assert results.include? @@test_dir_path + "/find_object_#{i}"
      end

      refute results.include? @@test_dir_path + '/dog_biscuit'
    ensure
      copies.times do |i|
        result, headers = @@client.delete_object(@@test_dir_path + "/find_object_#{i}")
        assert_equal result, true
        assert headers.is_a? Hash
      end

      result, headers = @@client.delete_object(@@test_dir_path + "/dog_biscuit")
      assert_equal result, true
      assert headers.is_a? Hash
    end
  end

  def test_find_subdirectory_regex
    copies = 15

    @@client.put_directory("#{@@test_dir_path}/a")
    @@client.put_directory("#{@@test_dir_path}/b")

    begin
      copies.times do |i|
        dir_name = i % 2 == 0 ? 'a' : 'b'
        @@client.put_object("#{@@test_dir_path}/#{dir_name}/find_object_#{i}", 'test_find_regex')
      end

      @@client.put_object(@@test_dir_path + '/dog_biscuit', 'dont match me')

      results = @@client.find(@@test_dir_path, regex: '^find_object_.*')

      assert_equal copies, results.length

      copies.times do |i|
        dir_name = i % 2 == 0 ? 'a' : 'b'
        assert results.include? "#{@@test_dir_path}/#{dir_name}/find_object_#{i}"
      end

      refute results.include? @@test_dir_path + '/dog_biscuit'
    ensure
      copies.times do |i|
        dir_name = i % 2 == 0 ? 'a' : 'b'
        result, headers = @@client.delete_object("#{@@test_dir_path}/#{dir_name}/find_object_#{i}")
        assert_equal result, true
        assert headers.is_a? Hash
      end

      result, headers = @@client.delete_object(@@test_dir_path + "/dog_biscuit")
      assert_equal result, true
      assert headers.is_a? Hash

      @@client.delete_directory("#{@@test_dir_path}/a")
      @@client.delete_directory("#{@@test_dir_path}/b")
    end
  end
end
