#!/bin/sh
# OpenBSD
set -ex
set -o pipefail

CALLBACK_URL="GARM_CALLBACK_URL"
BEARER_TOKEN="GARM_CALLBACK_TOKEN"
DOWNLOAD_URL="GH_DOWNLOAD_URL"
FILENAME="GH_FILENAME"
TARGET_URL="GH_TARGET_URL"
RUNNER_TOKEN="GH_RUNNER_TOKEN"
RUNNER_NAME="GH_RUNNER_NAME"
RUNNER_LABELS="GH_RUNNER_LABELS"

call() {
	PAYLOAD="$1"
	curl -s -X POST -d "${PAYLOAD}" -H 'Accept: application/json' -H "Authorization: Bearer ${BEARER_TOKEN}" "${CALLBACK_URL}" || echo "failed to call home: exit code ($?)"
}

sendStatus() {
	MSG="$1"
	call "{\"status\": \"installing\", \"message\": \"$MSG\"}"
}

success() {
	MSG="$1"
	call "{\"status\": \"idle\", \"message\": \"$MSG\"}"
}

fail() {
	MSG="$1"
	call "{\"status\": \"failed\", \"message\": \"$MSG\"}"
	exit 1
}

sync
hostname

PLATFORM=$( uname -s )

case "${PLATFORM}" in
	FreeBSD)
		ntpdate 0.freebsd.pool.ntp.org || true
		service ntpd onestart
		;;
	DragonFly)
		service dntpd onestart
		;;
	OpenBSD)
		rdate -s pool.ntp.org
		/etc/rc.d/ntpd start
		;;
	*)
esac

#adduser --disabled-password --gecos "Runner" runner

#cat > /etc/sudoers.d/100-runner <<EOF
#runner ALL=(ALL) NOPASSWD:ALL
#EOF

if [ "${PLATFORM}" = "OpenBSD" ]; then
	pkg_add -r wget curl
	hash -r || true
fi

#chmod 0400 /etc/sudoers.d/100-runner

[ ! -d /usr/local/bin ] && mkdir -p /usr/local/bin
[ ! -d /usr/local/etc/rc.d ] && mkdir -p /usr/local/etc/rc.d

sendStatus "downloading tools from ${DOWNLOAD_URL}"
#fetch -o /usr/local/bin/github-act-runner.gz https://myb.convectix.com/DL/gh/github-act-runner-dfly.gz

# OBSD:
cd /usr/local/bin/
wget -O github-act-runner.gz https://myb.convectix.com/DL/gh/github-act-runner-obsd.gz

#fetch -o /usr/local/etc/rc.d/github-act-runner https://myb.convectix.com/DL/gh/github-act-runner.rc
wget -O /etc/rc.d/github_act_runner https://myb.convectix.com/DL/gh/github_act_runner

sendStatus "extracting runner"

cd /usr/local/bin
gunzip /usr/local/bin/github-act-runner.gz

chmod +x /usr/local/bin/github-act-runner

case "${PLATFORM}" in
	OpenBSD)
		chmod +x /etc/rc.d/github_act_runner
		;;
	*)
		chmod +x /usr/local/etc/rc.d/github-act-runner
		;;
esac

sendStatus "installing dependencies"
case "${PLATFORM}" in
	OpenBSD)
		pkg_add -r bash git sudo curl
		;;
	*)
		pkg install -y bash git sudo curl
		;;
esac

hash -r || true

sendStatus "configuring runner"
#echo "sudo -u runner -- ./config.sh --unattended --url \"${TARGET_URL}\" --token \"${RUNNER_TOKEN}\" --name \"${RUNNER_NAME}\" --labels \"${RUNNER_LABELS}\" --ephemeral" >> /tmp/myrun.log
#sudo -u runner -- ./config.sh --unattended --url "${TARGET_URL}" --token "${RUNNER_TOKEN}" --name "${RUNNER_NAME}" --labels "${RUNNER_LABELS}" --ephemeral || fail "failed to configure runner"

# strip ' from CBSDfile ?
RNAME=$( echo ${RUNNER_NAME} | tr -d "\"" | tr -d "'" )

# workdir is relevant - settings.json!   ( --replace for overwrite )
cd /root
echo "/usr/local/bin/github-act-runner configure --unattended --url \"${TARGET_URL}\" --token \"${RUNNER_TOKEN}\" --name \"${RUNNER_NAME}\" --labels \"${RUNNER_LABELS}\" --ephemeral" >> /tmp/config.log
/usr/local/bin/github-act-runner configure --unattended --url "${TARGET_URL}" --token "${RUNNER_TOKEN}" --name "${RUNNER_NAME}" --labels "${RUNNER_LABELS}" --ephemeral || fail "failed to configure runner"

sendStatus "installing runner service"
case "${PLATFORM}" in
	FreeBSD)
		/usr/sbin/service github-act-runner enable
		;;
	DragonFly)
		echo github_act_runner_enable=YES >> /etc/rc.conf
		;;
esac

sendStatus "starting service"
#./svc.sh start || fail "failed to start service"

case "${PLATFORM}" in
	OpenBSD)
		/etc/rc.d/github_act_runner || true
		;;
	*)
		/usr/sbin/service github-act-runner start
		;;
esac

success "runner successfully installed"

exit 0
