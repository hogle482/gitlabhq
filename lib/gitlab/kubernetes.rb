module Gitlab
  # Helper methods to do with Kubernetes network services & resources
  module Kubernetes
    # This is the comand that is run to start a terminal session. Kubernetes
    # expects `command=foo&command=bar, not `command[]=foo&command[]=bar`
    EXEC_COMMAND = URI.encode_www_form(
      ['sh', '-c', 'bash || sh'].map { |value| ['command', value] }
    )

    # Filters an array of pods (as returned by the kubernetes API) by their labels
    def filter_pods(pods, labels = {})
      pods.select do |pod|
        metadata = pod.fetch("metadata", {})
        pod_labels = metadata.fetch("labels", nil)
        next unless pod_labels

        labels.all? { |k, v| pod_labels[k.to_s] == v }
      end
    end

    # Converts a pod (as returned by the kubernetes API) into a terminal
    def terminals_for_pod(api_url, namespace, pod)
      metadata = pod.fetch("metadata", {})
      status   = pod.fetch("status", {})
      spec     = pod.fetch("spec", {})

      containers = spec["containers"]
      pod_name   = metadata["name"]
      phase      = status["phase"]

      return unless containers.present? && pod_name.present? && phase == "Running"

      created_at = DateTime.parse(metadata["creationTimestamp"]) rescue nil

      containers.map do |container|
        {
          selectors:    { pod: pod_name, container: container["name"] },
          url:          container_exec_url(api_url, namespace, pod_name, container["name"]),
          subprotocols: ['channel.k8s.io'],
          headers:      Hash.new { |h, k| h[k] = [] },
          created_at:   created_at
        }
      end
    end

    def add_terminal_auth(terminal, token:, max_session_time:, ca_pem: nil)
      terminal[:headers]['Authorization'] << "Bearer #{token}"
      terminal[:max_session_time] = max_session_time
      terminal[:ca_pem] = ca_pem if ca_pem.present?
    end

    def container_exec_url(api_url, namespace, pod_name, container_name)
      url = URI.parse(api_url)
      url.path = [
        url.path.sub(%r{/+\z}, ''),
        'api', 'v1',
        'namespaces', ERB::Util.url_encode(namespace),
        'pods', ERB::Util.url_encode(pod_name),
        'exec'
      ].join('/')

      url.query = {
        container: container_name,
        tty: true,
        stdin: true,
        stdout: true,
        stderr: true
      }.to_query + '&' + EXEC_COMMAND

      case url.scheme
      when 'http'
        url.scheme = 'ws'
      when 'https'
        url.scheme = 'wss'
      end

      url.to_s
    end
  end
end
