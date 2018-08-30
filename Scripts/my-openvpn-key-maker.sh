#!/bin/bash -e

umask 266;
WorkingDir=`pwd`;

#
# Error Codes
#
EASY_RSA_REQUIRED=2
FAILED_TO_INIT_CA_PKI=3
FAILED_TO_INIT_CA_CERT=4
FAILED_TO_INIT_SERVER_PKI=5
FAILED_TO_GENERATE_SERVER_CERT_REQUEST=6
FAILED_TO_IMPORT_SERVER_CERT_REQUEST=7
FAILED_TO_SIGN_SERVER_CERT_REQUEST=8
FAILED_TO_CREATE_DIRECTORY=9
FAILED_TO_COPY_FILE=10
FAILED_TO_GENERATE_DH2048=11
NEW_CLIENT_NAME_EMPTY=12
CLIENT_DIRECTORY_EXISTS=13
FAILED_TO_INIT_CLIENT_PKI=14
FAILED_TO_GENERATE_CLIENT_CERT_REQUEST=15
FAILED_TO_IMPORT_CLIENT_CERT_REQUEST=16
FAILED_TO_SIGN_CLIENT_CERT_REQUEST=17
#
# Default Parameters
#
MyOpenVpnPath="/etc/my-openvpn"
ServerArtifactsDir="${MyOpenVpnPath}/server-files"
GenerateServerFiles=false
TempPath="/tmp/my-openvpn";
EasyRsaUrl="https://github.com/OpenVPN/easy-rsa/archive/v3.0.5.zip";
ZipFile="${TempPath}/v3.0.5.zip";
EazyRsaFolder="${TempPath}/easy-rsa-3.0.5"
EasyRsaInstallPath="/usr/local/easy-rsa-3.0.5";
ClientConfigPath="${WorkingDir}"

#
# Utility Functions
#
function show {
    printf "${1}";
}

function showLn {
    printf "${1}\n";
}

function showCmd {
    printf "\n> ${1}\n";
    eval ${1}
}

function abort {
    printf "\nAborting!\n"
    echo $1 >&2
    code=${2}
    if ((code > 0)); then
        exit ${code};
    fi
    exit $GENERAL_ERROR;
}

function easyRsaInstalled {
    showLn "Checking for EasyRSA";

    if command -v easyrsa >/dev/null 2>&1; then
        showLn "EasyRSA already available";
        return 0
    fi

    if [ -d ${EasyRsaInstallPath}/easyrsa3 ]; then
        PATH=${PATH}:${EasyRsaInstallPath}/easyrsa3;

        if command -v easyrsa >/dev/null 2>&1; then
            showLn "EasyRSA has been added to path";
            return 0
        fi
    fi

    return ${EASY_RSA_REQUIRED}
}

function easyRsaInstall {
    showLn "Installing EasyRSA";

    # remove any prior path if it existed
    test -d ${TempPath} && rm -rf ${TempPath};

    if [ ! -d ${TempPath} ]; then
        # create temporary path
        showCmd "mkdir -p ${TempPath};" || abort "Failed to create ${TempPath}." $FAILED_TO_CREATE_DIRECTORY;
    fi

    if command -v curl >/dev/null 2>&1; then
        showCmd "curl -sLo ${ZipFile} ${EasyRsaUrl}"
    elif command -v wget >/dev/null 2>&1; then
        wget ${EasyRsaUrl} -P ${ZipFile};
    fi

    if [ ! -f ${ZipFile} ]; then
        abort "Failed to download EasyRSA from ${EasyRsaUrl} to ${ZipFile}." ${EASY_RSA_REQUIRED};
    fi

    #overwrite, very quite
    showCmd "unzip -oq ${ZipFile} -d ${TempPath};" || abort "Failed to unzip ${ZipFile} to ${TempPath}." ${EASY_RSA_REQUIRED};

    if [ ! -d ${EazyRsaFolder} ]; then
        abort "Failed to find EasyRSA folder at the expected path: ${EazyRsaFolder}" ${EASY_RSA_REQUIRED};
    fi


    if [ -d ${EasyRsaInstallPath} ]; then
        rm -rf ${EasyRsaInstallPath};
    fi

    mv -f  ${EazyRsaFolder} ${EasyRsaInstallPath};

    rm -rf ${TempPath};

    printf "#!/bin/bash\nexport PATH=$PATH:${EasyRsaInstallPath}/easyrsa3;\n" > /etc/profile.d/my-openvpn-easyrsa-path.sh;

    showLn "EasyRSA now installed";
}

function complete {
    printf "\nComplete\n"
    exit 0
}

#
# Parameter Parsing
#
PARAMS=""

while (( "$#" )); do
  case "$1" in
    help)
      printf "
	-c --new-client <client name>	A unique name to assign to the client. Examples: BobSmith or WorkLaptop231
	-m --my-openvpn-path <path>	Path to the folder where files either exist or should be created
	-s --gen-server-files		if option is present then server files will be generated (unless they aready exist)
";
      shift 1
      complete
      ;;
    -m|--my-openvpn-path)
      if [ -z "${2}" ]; then
        show "\nPlease provide the directory path for the my-openvpn files: "
        read MyOpenVpnPath
        shift 1
      else
        MyOpenVpnPath=$2
        shift 2
      fi
      ;;
    -s|--gen-server-files)
	GenerateServerFiles=true
	  if [ -z "${2}" ]; then
	    show "\nPlease provide the directory path for the generated server artifacts: "
	    read ServerArtifactsDir
        shift 1
      else
        ServerArtifactsDir=$2
        shift 2
      fi
      ;;
    -c|--new-client)
      if [ -z "${2}" ]; then
        show "\nPlease provide the name for the new client: "
        read NewClientName
        shift 1
      else
        NewClientName=$2
        shift 2
      fi
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      abort "Error: Unsupported flag $1" $PARAM_ERROR
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

#
# Verify Easy RSA is available
#
if ! easyRsaInstalled; then
    easyRsaInstall;

    if ! easyRsaInstalled; then
        abort "Failed to install easyrsa" ${EASY_RSA_REQUIRED};
    fi
fi

#
# Set Easy RSA Variables
#
export EASYRSA_REQ_COUNTRY=Anonymous;
export EASYRSA_REQ_PROVINCE=Anonymous;
export EASYRSA_REQ_CITY=Anonymous;
export EASYRSA_REQ_ORG=Anonymous;
export EASYRSA_REQ_EMAIL=Anonymous;
export EASYRSA_REQ_OU=Anonymous;

#
# Verify Directory Structure
#
Paths="${MyOpenVpnPath} ${CaDir} ${ClientsDir} ${ServerDir}";

for i in ${Paths}; do
	if [ ! -d ${i} ]; then 
		showLn "Creating directory: ${i}";
		mkdir -p ${i} || abort "Failed to create directory: ${i}" ${FAILED_TO_CREATE_DIRECTORY};
	fi
done

function gen_ca_files {
	export EASYRSA_REQ_CN=AnonymousCA;
	CaDir="${MyOpenVpnPath}/ca"
	CaPkiDir="${MyOpenVpnPath}/ca/pki"
	#
	# Look for CA PKI
	#
	if [ ! -d ${CaPkiDir} ]; then
		showLn "Initializing CA PKI in ${CaPkiDir}"
		showCmd "easyrsa --batch --pki-dir=${CaPkiDir} init-pki" || abort "Failed to initailize CA PKI" ${FAILED_TO_INIT_CA_PKI};
	fi


	if [ ! -f ${CaDir}/pki/private/ca.key ]; then
		showLn "Initailizing CA Certificate"
		showCmd "easyrsa --batch --pki-dir=${CaPkiDir} build-ca nopass" || abort "Failed to build CA certificate" ${FAILED_TO_INIT_CA_CERT};
	fi
}

function gen_server_files {
	export EASYRSA_REQ_CN=AnonymousServer;
	ServerCertName="my-openvpn-server";
	ServerDir="${MyOpenVpnPath}/server"
	ServerPkiDir="${ServerDir}/pki"

	#
	# Look for Server PKI
	#
	if [ ! -d ${ServerPkiDir} ]; then
		showLn "Initializing Server PKI in ${ServerPkiDir}";
		showCmd "easyrsa --batch --pki-dir=${ServerPkiDir} init-pki" || abort "Failed to initialize Server PKI" ${FAILED_TO_INIT_SERVER_PKI};
	fi

	#
	# Ensure the artifacts directory exists
	#
	if [ ! -d ${ServerArtifactsDir} ]; then
        mkdir -p ${ServerArtifactsDir} || abort "Failed to create directory: ${ServerArtifactsDir}" ${FAILED_TO_CREATE_DIRECTORY}
    fi

    #
    # If the ca.crt is not in the artifacts directory, put it there
    #
    if [ ! -f ${ServerArtifactsDir}/ca.crt ]; then
        NextFile="${CaPkiDir}/ca.crt";
    	cp ${NextFile} ${ServerArtifactsDir}/ca.crt || abort "Failed to copy ${NextFile} to ${ServerArtifactsDir}/ca.crt" ${FAILED_TO_COPY_FILE};
    fi

    #
    # If the server.crt or server.key files are missing, create them and put them in the artifacts directory
    #
    if [ ! -f ${ServerArtifactsDir}/server.crt ] || [ ! -f ${ServerArtifactsDir}/server.key ]; then
		showLn "Creating Server Certificate Request: ${ServerCertName}";
		showCmd "easyrsa --batch --pki-dir=${ServerPkiDir} gen-req ${ServerCertName} nopass" || abort "Failed to generate server request." ${FAILED_TO_GENERATE_SERVER_CERT_REQUEST};

		showLn "Importing Server Certificate Request to CA";
		ServerRequestFile=${ServerPkiDir}/reqs/${ServerCertName}.req;
		showCmd "easyrsa --batch --pki-dir=${CaPkiDir} import-req ${ServerRequestFile} ${ServerCertName}" || abort "Failed to import Server certificate request" ${FAILED_TO_IMPORT_SERVER_CERT_REQUEST};

		showLn "Signing Request to Create Server Certificate"
		showCmd "easyrsa --batch --pki-dir=${CaPkiDir} sign-req server ${ServerCertName} nopass" || abort "Failed to sign Server Certificate Request" ${FAILED_TO_SIGN_SERVER_CERT_REQUEST};

		NextFile="${CaPkiDir}/issued/${ServerCertName}.crt";
		cp ${NextFile} ${ServerArtifactsDir}/server.crt || abort "Failed to copy ${NextFile} to ${ServerArtifactsDir}/server.crt" ${FAILED_TO_COPY_FILE};

		NextFile="${ServerPkiDir}/private/${ServerCertName}.key";
		cp ${NextFile} ${ServerArtifactsDir}/server.key || abort "Failed to copy ${NextFile} to ${ServerArtifactsDir}/server.key" ${FAILED_TO_COPY_FILE};
    fi

    #
    # If the dh2048.pem file is missing, create it and put it in the artifacts directory
    #
    if [ ! -f ${ServerArtifactsDir}/dh2048.pem ]; then
		showCmd "easyrsa --batch --pki-dir=${ServerPkiDir} gen-dh" || abort "Failed to generate dh2048.pem" ${FAILED_TO_GENERATE_DH2048}

		NextFile="${ServerPkiDir}/dh.pem"
		cp ${NextFile} ${ServerArtifactsDir}/dh2048.pem || abort "Failed to copy ${NextFile} to ${ServerArtifactsDir}/dh2048.pem" ${FAILED_TO_COPY_FILE};
	fi 
}

function gen_new_client {
	Name="$1"
	export EASYRSA_REQ_CN=${Name};
	ClientsDir="${MyOpenVpnPath}/clients"
	ClientDir="${ClientsDir}/${Name}"
	ClientPkiDir="${ClientDir}/pki"
	ClientCertName="${Name}"
	if [ -z "${Name}" ]; then 
		abort "New Client Name cannot be empty." ${NEW_CLIENT_NAME_EMPTY}
	fi

	if [ ! -d "${ClientPkiDir}" ]; then
        showLn "Initializing Server PKI in ${ClientPkiDir}";
        showCmd "easyrsa --batch --pki-dir=${ClientPkiDir} init-pki" || abort "Failed to initialize Client PKI" ${FAILED_TO_INIT_CLIENT_PKI};
	fi

    ClientRequestFile=${ClientPkiDir}/reqs/${ClientCertName}.req;
    if [ ! -d "${ClientRequestFile}" ]; then
        showLn "Creating Client Certificate Request: ${ClientCertName}";
        showCmd "easyrsa --batch --pki-dir=${ClientPkiDir} gen-req ${ClientCertName} nopass" || abort "Failed to generate client request." ${FAILED_TO_GENERATE_CLIENT_CERT_REQUEST};
    fi

    ClientCertFile=${CaPkiDir}/issued/${ClientCertName}.crt;
    if [ ! -d "${ClientCertFile}" ]; then
        showLn "Importing Client Certificate Request to CA";
        showCmd "easyrsa --batch --pki-dir=${CaPkiDir} import-req ${ClientRequestFile} ${ClientCertName}" || abort "Failed to import Client certificate request" ${FAILED_TO_IMPORT_CLIENT_CERT_REQUEST};

        showLn "Signing Request to Create Client Certificate"
        showCmd "easyrsa --batch --pki-dir=${CaPkiDir} sign-req client ${ClientCertName} nopass" || abort "Failed to sign Client Certificate Request" ${FAILED_TO_SIGN_CLIENT_CERT_REQUEST};
    fi

	ClientConfig=${ClientConfigPath}/${Name}.ovpn
	printf "
client
dev tun
proto udp
resolv-retry infinite
nobind
user nobody
group nobody
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
" > ${ClientConfig};

	printf "\n<ca>\n`cat ${CaPkiDir}/ca.crt`\n</ca>\n" >> ${ClientConfig}
	printf "\n<cert>\n`cat ${ClientCertFile}`\n</cert>\n" >> ${ClientConfig}
	printf "\n<key>\n`cat ${ClientPkiDir}/private/${ClientCertName}.key`\n</key>\n" >> ${ClientConfig}
	chmod 400 ${ClientConfig};
	showLn "\nClient Certificate Generated: ${ClientConfig}\n"
}

gen_ca_files;

if [ "${GenerateServerFiles}" = true ]; then
	gen_server_files;
fi

if [ ! -z "${NewClientName}" ]; then
	gen_new_client ${NewClientName}
fi

complete
