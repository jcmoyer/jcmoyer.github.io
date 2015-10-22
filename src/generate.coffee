liquid = require 'liquid-node'
marked = require 'marked'
moment = require 'moment'
yaml   = require 'js-yaml'
Promise = require 'bluebird'
program = require 'commander'
mkdirp = require 'mkdirp'
hljs = require 'highlight.js'

fs     = require 'fs'
path   = require 'path'

marked.setOptions {
  highlight: (code, lang) ->
    hljs.highlight(lang, code).value
}

renderer = new marked.Renderer()

# ported from marked
escape = (html, encode) ->
  html
    .replace (if not encode then /&(?!#?\w+;)/g else /&/g), '&amp;'
    .replace /</g, '&lt;'
    .replace />/g, '&gt;'
    .replace /"/g, '&quot;'
    .replace /'/g, '&#39;'

# based on code function from marked
renderer.code = (code, lang) ->
  if @options.highlight
    out = @options.highlight(code, lang)
    if `out != null && out !== code`
      escaped = true
      code = out
  output = if escaped then code else escape(code, true)
  return "<pre><code class=\"hljs\">#{output}</code></pre>"

resolveTemplateFilename = (filename) ->
  path.posix.join('templates', filename)

resolvePostFilename = (filename) ->
  path.posix.join('posts', filename)

# resolves filenames to the templates/ directory
# e.g. abc -> templates/abc.html
class TemplateFileSystem extends liquid.BlankFileSystem
  # so apparently this chops off extensions...
  readTemplateFile: (path) ->
    new Promise (resolve, reject) ->
      fs.readFile resolveTemplateFilename(path) + '.html', (err, data) ->
        if err
          reject()
        else
          resolve data.toString 'utf-8'

class Post
  constructor: (@filename, @title, @date) ->
    @fmtDate   = @date.format('MMMM D, YYYY')
    @timestamp = @date.unix()
    @link      = resolvePostFilename (@title.replace /\s+/g, '_') + '.html'

readPostMetadata = (filename, f) ->
  fs.readFile filename, (err, data) ->
    if err
      f err
    blogData = yaml.safeLoad data.toString 'utf-8'
    f null, blogData

program
  .option '-o, --output [directory]', 'write output to [directory]', '.'
  .parse process.argv

writeOutputFile = (filename, data) ->
  mkdirp path.dirname(filename), ->
    fs.writeFile filename, data, (err) ->
      if err
        console.log err
      else
        console.log "wrote #{filename}"

exports.run = ->
  readPostMetadata 'blog.yaml', (err, blog) ->
    # create Post objects for each entry in config file
    posts = (new Post(p.filename, p.title, moment(p.date)) for p in blog.posts)

    engine = new liquid.Engine
    engine.fileSystem = new TemplateFileSystem

    # read index template and process it
    fs.readFile resolveTemplateFilename('index.html'), (err, data) ->
      templateStr = data.toString 'utf-8'
      engine.parse templateStr
        .then (t) -> t.render {blog: blog, posts: posts}
        .then (s) -> writeOutputFile path.join(program.output, 'index.html'), s

    # read about template and process it
    fs.readFile resolveTemplateFilename('about.html'), (err, data) ->
      templateStr = data.toString 'utf-8'
      engine.parse templateStr
        .then (t) -> t.render {blog: blog}
        .then (s) -> writeOutputFile path.join(program.output, 'about.html'), s

    # read post template and generate posts
    fs.readFile resolveTemplateFilename('post.html'), (err, data) ->
      templateStr = data.toString 'utf-8'
      engine.parse templateStr
        .then (t) ->
          posts.forEach (post) ->
            fs.readFile resolvePostFilename(post.filename), (err, data) ->
              postStr = data.toString 'utf-8'
              t.render {blog: blog, post: post, content: marked(postStr, {renderer: renderer})}
                .then (s) -> writeOutputFile path.join(program.output, post.link), s

