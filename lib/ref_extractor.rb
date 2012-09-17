# Module providing an extract_ref method for controllers working with Git
# tree-ish + path params
module RefExtractor
  # Thrown when given an invalid path
  class InvalidPathError < StandardError; end

  # Given a string containing both a Git ref - such as a branch or tag - and a
  # filesystem path joined by forward slashes, attempts to separate the two.
  #
  # Expects a @project instance variable to contain the active project. Used to
  # check the input against a list of valid repository refs.
  #
  # Examples
  #
  #   # No @project available
  #   extract_ref('master')
  #   # => ['', '']
  #
  #   extract_ref('master')
  #   # => ['master', '']
  #
  #   extract_ref("f4b14494ef6abf3d144c28e4af0c20143383e062/CHANGELOG")
  #   # => ['f4b14494ef6abf3d144c28e4af0c20143383e062', 'CHANGELOG']
  #
  #   extract_ref("v2.0.0/README.md")
  #   # => ['v2.0.0', 'README.md']
  #
  #   extract_ref('issues/1234/app/models/project.rb')
  #   # => ['issues/1234', 'app/models/project.rb']
  #
  #   # Given an invalid branch, we fall back to just splitting on the first slash
  #   extract_ref('non/existent/branch/README.md')
  #   # => ['non', 'existent/branch/README.md']
  #
  # Returns an Array where the first value is the tree-ish and the second is the
  # path
  def extract_ref(input)
    pair = ['', '']

    return pair unless @project

    if input.match(/^([[:alnum:]]{40})(.+)/)
      # If the ref appears to be a SHA, we're done, just split the string
      pair = $~.captures
    else
      # Otherwise, attempt to detect the ref using a list of the project's
      # branches and tags

      # Append a trailing slash if we only get a ref and no file path
      id = input
      id += '/' unless id.include?('/')

      valid_refs = @project.branches + @project.tags
      valid_refs.select! { |v| id.start_with?("#{v}/") }

      if valid_refs.length != 1
        # No exact ref match, so just try our best
        pair = id.match(/([^\/]+)(.*)/).captures
      else
        # Partition the string into the ref and the path, ignoring the empty first value
        pair = id.partition(valid_refs.first)[1..-1]
      end
    end

    # Remove leading slash from path
    pair[1].gsub!(/^\//, '')

    pair
  end

  # Assigns common instance variables for views working with Git tree-ish objects
  #
  # Assignments are:
  #
  # - @id     - A string representing the joined ref and path
  # - @ref    - A string representing the ref (e.g., the branch, tag, or commit SHA)
  # - @path   - A string representing the filesystem path
  # - @commit - A CommitDecorator representing the commit from the given ref
  # - @tree   - A TreeDecorator representing the tree at the given ref/path
  #
  # Automatically renders `not_found!` if a valid tree could not be resolved
  # (e.g., when a user inserts an invalid path or ref).
  def assign_ref_vars
    @ref, @path = extract_ref(params[:id])

    @id = File.join(@ref, @path)

    @commit = CommitDecorator.decorate(@project.commit(@ref))

    @tree = Tree.new(@commit.tree, @project, @ref, @path)
    @tree = TreeDecorator.new(@tree)

    raise InvalidPathError if @tree.invalid?
  rescue NoMethodError, InvalidPathError
    not_found!
  end
end
