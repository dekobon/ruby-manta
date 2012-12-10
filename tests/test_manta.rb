require 'minitest/autorun'
require File.expand_path('../../lib/manta', __FILE__)

class TestManta < MiniTest::Unit::TestCase
  def setup
    host  = ENV['HOST']
    key   = ENV['KEY' ]
    @user = ENV['USER']

    unless host && key && @user
      puts 'Require HOST, USER and KEY to run tests.'
      exit
    end

    priv_key_data = File.read(key)
    http_client, fingerprint, priv_key = Manta.prepare(priv_key_data, :disable_ssl_verification => true)

    @client = Manta.new(http_client, host, @user, fingerprint, priv_key)
  end



  def test_paths
    begin
      @client.put_directory("/not-me/stor/ruby-manta-test")
      assert false
    rescue ArgumentError
    end
    # ...
  end



  def test_directories
    test_dir_path = '/%s/stor/ruby-manta-test' % @user

    result, headers = @client.put_directory(test_dir_path)
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.put_directory(test_dir_path + '/dir1')
    assert_equal result, true
    assert headers.is_a? Hash

    # since idempotent
    result, headers = @client.put_directory(test_dir_path + '/dir1')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.put_object(test_dir_path + '/obj1', 'obj1-data')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.put_object(test_dir_path + '/obj2', 'obj2-data')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.list_directory(test_dir_path)
    assert headers.is_a? Hash
    assert_equal result.size, 3

    assert_equal result[0]['name'], 'dir1'
    assert_equal result[0]['type'], 'directory'
    assert result[0]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/)

    assert_equal result[1]['name'], 'obj1'
    assert_equal result[1]['type'], 'object'
    assert_equal result[1]['size'], 9
    assert result[1]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/)

    assert_equal result[2]['name'], 'obj2'
    assert_equal result[2]['type'], 'object'
    assert_equal result[2]['size'], 9
    assert result[2]['mtime'].match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/)

    result, _ = @client.list_directory(test_dir_path, :limit => 2)
    assert_equal result.size, 2
    assert_equal result[0]['name'], 'dir1'
    assert_equal result[1]['name'], 'obj1'

    result, _ = @client.list_directory(test_dir_path, :limit => 1)
    assert_equal result.size, 1
    assert_equal result[0]['name'], 'dir1'

    result, _ = @client.list_directory(test_dir_path, :limit  => 2,
				                      :marker => 'obj1')
    assert_equal result.size, 2
    assert_equal result[0]['name'], 'obj1'
    assert_equal result[1]['name'], 'obj2'

    result, headers = @client.list_directory(test_dir_path, :head => true)
    assert_equal result, true
    assert_equal headers['Result-Set-Size'], '3'

    begin
      @client.delete_directory(test_dir_path)
      assert false
    rescue Manta::DirectoryNotEmpty
    end

    result, _ = @client.delete_directory(test_dir_path + '/dir1')
    assert_equal result, true
    result, _ = @client.delete_object(test_dir_path + '/obj1')
    assert_equal result, true
    result, _ = @client.delete_object(test_dir_path + '/obj2')
    assert_equal result, true

    result, headers = @client.delete_directory(test_dir_path)
    assert_equal result, true
    assert headers.is_a? Hash

    begin
      @client.list_directory(test_dir_path + '/does-not-exist')
      assert false
    rescue Manta::ResourceNotFound
    end

    begin
      @client.put_directory(test_dir_path + '/dir1')
      assert false
    rescue Manta::DirectoryDoesNotExist
    end
  end



  def test_objects
    test_dir_path = '/%s/stor/ruby-manta-test' % @user

    result, headers = @client.put_directory(test_dir_path)
    assert_equal result, true

    result, headers = @client.put_object(test_dir_path + '/obj1', 'foo-data')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.get_object(test_dir_path + '/obj1')
    assert_equal result, 'foo-data'
    assert_equal headers['Content-Type'], 'application/x-www-form-urlencoded'

    result, headers = @client.put_object(test_dir_path + '/obj1', 'bar-data',
                                         :content_type     => 'application/wacky',
                                         :durability_level => 3)
    assert_equal result, true

    result, headers = @client.get_object(test_dir_path + '/obj1')
    assert_equal result, 'bar-data'
    assert_equal headers['Content-Type'], 'application/wacky'

    result, headers = @client.get_object(test_dir_path + '/obj1', :head => true)
    assert_equal result, true
    assert_equal headers['Content-Type'], 'application/wacky'

    begin
      @client.put_object(test_dir_path + '/obj1', 'bar-data',
                         :durability_level => 999)
      assert false
    rescue Manta::InvalidDurabilityLevel
    end

    begin
      @client.get_object(test_dir_path + '/does-not-exist')
      assert false
    rescue Manta::ResourceNotFound
    end

    begin
      @client.delete_object(test_dir_path + '/does-not-exist')
      assert false
    rescue Manta::ResourceNotFound
    end

    result, headers = @client.delete_object(test_dir_path + '/obj1')
    assert_equal result, true
    assert headers.is_a? Hash

    result, headers = @client.delete_directory(test_dir_path)
    assert_equal result, true
  end



#  def test_public
#  end



#  def test_signed_urls
#    @client.gen_signed_url(Time.now + 500000, :get, "/#{@user}/stor/foo", [[ 'bar', 'beep' ]])
#  end



#  def test_links
#    @client.put_link("/#{@user}/stor/foo", "/#{@user}/stor/falafel")
#  end



#  def test_jobs
#    path, _  = @client.create_job({ phases: [{ exec: 'grep foo' }] })
#    @client.get_job(path)
#    @client.list_jobs(:all)
#    @client.add_job_keys(path, ["/#{@user}/stor/foo", "/#{@user}/stor/falafel"])
#    sleep(5)
#    @client.get_job_input(path)
#    @client.get_job_output(path)
#    @client.get_job_failures(path)
#    @client.get_job_errors(path)
#    @client.cancel_job(path)
#  end



#  def test_many_objects
	  # listing
	  # jobs
#  end
end