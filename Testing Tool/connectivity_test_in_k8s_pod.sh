# Executed in bash, kubectl and python 3 required.
# This script will spawn a new pod under inputted namespace and execute curl tests
# The script will also try to find out the solution

BASEDIR=$(dirname "$0")

help_function(){
	echo ""
	echo "Usage: $0 -n NAMESPACE -u URL -e testing environment [-i] [-d domain resolve]"
	echo -e "\t-n Namespace to deploy app for testing"
	echo -e "\t-u URL to be called for checking network connection"
	# echo -e "\t-e Testing environment, for selecting docker image source" # TODO
	echo -e "\t-i (Optional) Test connection without sidecar if exists"
	echo -e "\t-d (Optional) To specify ip address for your domain"
	exit 1 # Exit script after printing help
}

result_handler(){
	status_code=$1 # 0: Success, 1: Failure
	url=$2
	message="$3"
	status=""
	echo "======================================="
	case $status_code in
		0)
			status="SUCCESS";;
		1)
			status="FAILURE";;
		?)
			status="UNKNOWN";;
	esac
	echo "[${url}][${status}] ${message}";
	if [[ ! -z "$RESULT_OUTPUT_FILE" ]]; then
		echo "[${url}][${status}] ${message}" >> "$RESULT_OUTPUT_FILE"
	fi
	echo "======================================="
}

check_service_entry(){
	namespace_se="$1"
	url="$2"
	is_export_to_all="$3"
	json_path="${namespace_se}_$(date +%Y%m%d%H%M%S)"
	"${KUBECTL}" get se -n "$namespace_se" -o json > "${BASEDIR}/${json_path}"
	"${PYTHON}" "${BASEDIR}/service_entry_checker.py" "${BASEDIR}/${json_path}" "${url}" "${is_export_to_all}"
	exit_code="$?"
	rm "${BASEDIR}/${json_path}"
	return "${exit_code}"
}
check_service_entry_existence(){
	url=$1
	echo "Check service entry existence"

	check_service_entry "${NAMESPACE}" "${url}" "false"
	exit_code=$?
	[ ${exit_code} == 0 ] && return 0
	
	result_handler 1 "${url}" "Missing service entry"
	return 1
}
access_blocked_check(){
	url=$1
	check_service_entry_existence "${url}"
	if [ $? == 0 ]; then
		result_handler 1 "${url}" "Service entry found. Please check firewall status"
	fi
}

error_diagnostic(){
	url=$1
	case $2 in	#exit_code
		1)
			result_handler 0 "${url}" "Normal Connection with wrong http version."
			return;;
		6) 
			result_handler 1 "${url}" "Please confirm your url is correct."
			return;;
		35|56)
			access_blocked_check ${url}
			return;;
		52)
			result_handler 0 "${url}" "Normal Connection with empty reply."
			return;;
	esac

	case $3 in	#http_code
		200|302)
			result_handler 0 "${url}" "Normal connection."
			return;;
		401)
			result_handler 0 "${url}" "Normal connection. No permission to access."
			return;;
		400|403|404)
			result_handler 0 "${url}" "Normal connection. Please check application status for connection error."
			return;;
		502)
			access_blocked_check ${url}
			return;;
	esac

	echo "[Failure] Unexpected error"
}

network_connection_test(){
	url=$1
	pod_name=$($KUBECTL get pods -n $NAMESPACE --selector=app=$APP -o name | head -n 1)
	curl_command="curl ${url} -w \nhttp_code:%{http_code}\n -kv "
	if [[ ! -z "$DOMAIN_RESOLVE" ]]; then
		curl_command="${curl_command} --resolve ${DOMAIN_RESOLVE}"
	fi

	echo "Connecting to ${url} from pod ${pod_name}..."
	curl_response=$($KUBECTL exec -it ${pod_name} -n "${NAMESPACE}" -- ${curl_command})
	exit_code=$?
	echo "Exit code: ${exit_code}"
	echo "$curl_response"

	http_code=$(echo "$curl_response" | grep http_code: | sed -e "s/http_code://g")

	error_diagnostic ${url} ${exit_code} ${http_code}
}

check_pod_running(){
	pods_phase=$("${KUBECTL}" get pods -n ${NAMESPACE} --selector=app=${APP} -o jsonpath="{.items[0].status.phase}")
	exit_code=$?
	echo "exit_code: ${exit_code}"
	echo "pods_phase: ${pods_phase}"
	[ ${exit_code} != 0 ] \
		&& echo "${pods_phase}" \
		&& return ${exit_code}
	[ ${pods_phase} != "Running" ] \
		&& echo "Pod status: ${pods_phase}" \
		&& return 1
	return 0
}
check_istio_sidecar_removed(){
	pods_info=$("${KUBECTL}" get pods -n ${NAMESPACE} --selector=app=${APP} -o jsonpath="{range .items[*]}{.spec.containers[*].image}{\"\t\"}{.status.phase}{'\n'}{end}")
	exit_code=$?
	[ ${exit_code} != 0 ] \
		&& echo "${pods_info}" \
		&& return ${exit_code}

	pods_count=$(echo "${pods_info}" | wc -l)
	if [ ${pods_count} -gt 1 ]; then
		echo "Pods restarting"
		return 1
	fi
	if [[ ${pods_info} == *"istio"* ]]; then
		echo "Istio sidecar exists"
		return 1
	fi

	return 0
}
cleanup(){
	"${KUBECTL}" delete ServiceAccount ${APP} -n ${NAMESPACE}
	"${KUBECTL}" delete Service ${APP} -n ${NAMESPACE}
	"${KUBECTL}" delete Deployment ${APP} -n ${NAMESPACE}
}

while getopts "n:u:e:id:o:" opt
do
	case $opt in
		n)	NAMESPACE="${OPTARG}";;
		u)	URL_INPUT="${OPTARG}";;
		# e)	ENVIRONMENT="${OPTARG}";;
		i)	WITHOUT_ISTIO_FLAG="true";;
		d)	DOMAIN_RESOLVE="${OPTARG}";;
		o)  RESULT_OUTPUT_FILE="${OPTARG}";;
		? ) help_function ;;
	esac
done


KUBECTL="kubectl"
PYTHON="python"

APP="network-utils"
environment_yaml_path_default="${BASEDIR}/default.yaml"

RETRY_LIMIT=6
WAIT_PERIOD=10

if [ -z "$NAMESPACE" ] || [ -z "$URL_INPUT" ]; then
	echo "Missing input(s), connectivity_test.sh -n {NAMESPACE} -u {URL_INPUT}"
	exit 1
fi

# TODO: Support multiple yaml as testing environment
environment_yaml_path="${environment_yaml_path_default}"

if [[ ! -z "$RESULT_OUTPUT_FILE" ]]; then
	echo -n "" > "${RESULT_OUTPUT_FILE}"
fi

echo "Testing at: $($KUBECTL config current-context)"
echo "Namespace: ${NAMESPACE}"
echo "URL Input: ${URL_INPUT}"

if [[ ! -z "$WITHOUT_ISTIO_FLAG" ]]; then
	echo "Testing without sidecar: ${WITHOUT_ISTIO_FLAG}"
fi
if [[ ! -z "$DOMAIN_RESOLVE" ]]; then
	echo "Domain Resolve: ${DOMAIN_RESOLVE}"
fi

echo "Setup testing environment"
$KUBECTL apply -f "${environment_yaml_path}" -n ${NAMESPACE}
$KUBECTL get pods -n $NAMESPACE --selector=app=$APP
sleep $WAIT_PERIOD

echo "Check pod status"
success=0
retries=${RETRY_LIMIT}
while [ ${retries} -gt 0 ] && [ ${success} == 0 ]
do
	check_pod_running
	exit_code=$?
	echo "$exit_code"

	if [ $exit_code == 0 ]; then
		success=1
		break
	fi
	echo "Sleep ${WAIT_PERIOD}s for next check for retrying ${retries} time(s) more"
	sleep $WAIT_PERIOD
	retries=$(expr ${retries} - 1)
done

if [ ${success} == 0 ]; then
	echo "[Error]: Fail to create testing pod."
	cleanup
	exit 1
fi


echo "Test with sidecar"

for URL in ${URL_INPUT};
do
	network_connection_test ${URL}
done


if [ "$WITHOUT_ISTIO_FLAG" == "true" ]; then
	echo "Test without sidecar"
	
	echo "Remove sidecar from namespace $NAMESPACE"
	$KUBECTL label namespace $NAMESPACE istio-injection-
	exit_code=$?
	if [ $exit_code != 0 ] ; then
		echo "[Error] Fail to remove sidecar from namespace $NAMESPACE"
	else
		$KUBECTL rollout restart deployment ${APP} -n $NAMESPACE
		success=0
		retries=${RETRY_LIMIT}
		$KUBECTL get pods -n $NAMESPACE --selector=app=$APP
		while [ ${retries} -gt 0 ] && [ ${success} == 0 ]
		do
			check_istio_sidecar_removed
			exit_code=$?

			if [ $exit_code == 0 ]; then
				success=1
				break
			fi
			echo "Sleep ${WAIT_PERIOD}s for next check for retrying ${retries} time(s) more"
			sleep $WAIT_PERIOD
			retries=$(expr ${retries} - 1)
		done
		if [ ${success} == 0 ]; then
			echo "[Error] Fail to remove sidecar from namespace $NAMESPACE"
			exit 1
		fi
		
		for URL in ${URL_INPUT};
		do
			network_connection_test ${URL}
		done
	fi
	$KUBECTL label namespace $NAMESPACE istio-injection=enabled
fi

cleanup

if [[ ! -z "$RESULT_OUTPUT_FILE" ]]; then
	echo "======================================="
	echo "You can find the result output at $RESULT_OUTPUT_FILE"
fi