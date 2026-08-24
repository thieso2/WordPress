# frozen_string_literal: true

require "open3"
require "tempfile"

module Presentation
  # The oracle, asked once per spec run, about the three things this family computes:
  # which template renders a URL, what the body classes are, and what the title is.
  #
  # ⚠️ DIFFERENTIAL, for the same reason Composition::Parser's spec is: the 431 rules were
  # verified by READING the legacy, never by executing it. A hand-written expectation here
  # would only re-assert the author's reading of template-loader.php — which is precisely
  # the class of mistake the oracle exists to catch. Six of the eighteen screens depend on
  # a `get_*_template()` returning '' and the loop CONTINUING, and no one would think to
  # write that expectation from memory.
  module SpecOracle
    BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

    # The corpus paths, from spec/parity/corpus/requests.yml.
    PATHS = {
      "web.index" => "/",
      "web.singular" => "/2026/03/hello-world/",
      "web.page" => "/parent-page/",
      # ⚠️ Added by the verification pass. Not a golden screen — the corpus has no nested
      # page URL — but `get_body_class()` has a whole branch (post-template.php:723) that
      # only a page WITH a parent AND a child reaches: `page-parent`, `page-child` and
      # `parent-pageid-N`. Removing any of the three used to leave every example green.
      "web.page_child" => "/parent-page/child-page/",
      "web.archive" => "/2026/",
      "web.category" => "/category/top-category/",
      "web.tag" => "/tag/flat-tag-one/",
      "web.taxonomy" => "/category/top-category/middle-category/",
      "web.author" => "/author/oracle_author/",
      "web.date" => "/2026/03/",
      "web.search" => "/?s=article",
      "web.not_found_404" => "/definitely-not-a-real-url/",
      "web.embed" => "/2026/03/hello-world/embed/",
      "web.privacy_policy" => "/privacy-policy/",
    }.freeze

    module_function

    def available? = File.exist?(BOOTSTRAP) && !`which php`.strip.empty?

    def screens
      @screens ||= run(<<~PHP)
        $paths = json_decode('#{JSON.generate(PATHS)}', true);
        $tags = array(
          'is_embed' => 'get_embed_template', 'is_404' => 'get_404_template',
          'is_search' => 'get_search_template', 'is_front_page' => 'get_front_page_template',
          'is_home' => 'get_home_template', 'is_privacy_policy' => 'get_privacy_policy_template',
          'is_post_type_archive' => 'get_post_type_archive_template',
          'is_tax' => 'get_taxonomy_template', 'is_attachment' => 'get_attachment_template',
          'is_single' => 'get_single_template', 'is_page' => 'get_page_template',
          'is_singular' => 'get_singular_template', 'is_category' => 'get_category_template',
          'is_tag' => 'get_tag_template', 'is_author' => 'get_author_template',
          'is_date' => 'get_date_template', 'is_archive' => 'get_archive_template',
        );
        $types = array('404','archive','attachment','author','category','date','embed',
                       'frontpage','home','index','page','paged','privacypolicy','search',
                       'single','singular','tag','taxonomy');
        $GLOBALS['HIER'] = array();
        foreach ($types as $t) {
          add_filter("{$t}_template_hierarchy", function ($templates) use ($t) {
            $GLOBALS['HIER'][$t] = $templates; return $templates;
          }, 1);
        }
        $out = array();
        foreach ($paths as $screen => $path) {
          $GLOBALS['HIER'] = array();
          $GLOBALS['_wp_current_template_id'] = null;
          $_SERVER['REQUEST_URI'] = $path;
          $qs = parse_url($path, PHP_URL_QUERY);
          $_GET = array(); if ($qs) { parse_str($qs, $_GET); }
          $_SERVER['QUERY_STRING'] = $qs ? $qs : '';
          $GLOBALS['wp_query'] = new WP_Query();
          $GLOBALS['wp_the_query'] = $GLOBALS['wp_query'];
          $GLOBALS['wp'] = new WP();
          $GLOBALS['wp']->main('');
          $template = false;
          foreach ($tags as $tag => $getter) {
            if (call_user_func($tag)) { $template = call_user_func($getter); }
            if ($template) { break; }
          }
          if (!$template) { $template = get_index_template(); }
          $out[$screen] = array(
            'template_id' => $GLOBALS['_wp_current_template_id'],
            'loaded_file' => $template,
            'hierarchy' => $GLOBALS['HIER'],
            'body_class' => get_body_class(),
            'title' => wp_get_document_title(),
            'is_404' => is_404(),
          );
        }
        echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
      PHP
    end

    # The inputs the screens are built from, taken from the oracle rather than typed out:
    # ids, slugs and display names all appear in the answers being compared, so reading
    # them from anywhere else would be comparing the oracle against itself.
    def corpus
      @corpus ||= run(<<~PHP)
        $out = array('options' => array(), 'terms' => array(), 'users' => array(), 'posts' => array());
        foreach (array('blogname','blogdescription','show_on_front','page_on_front',
                       'page_for_posts','wp_page_for_privacy_policy','stylesheet','template',
                       'posts_per_page') as $o) {
          $out['options'][$o] = get_option($o);
        }
        foreach (array(array('category','top-category'), array('category','middle-category'),
                       array('post_tag','flat-tag-one')) as $pair) {
          $t = get_term_by('slug', $pair[1], $pair[0]);
          if ($t) {
            $out['terms'][] = array('taxonomy' => $pair[0], 'id' => (int) $t->term_id,
                                    'slug' => $t->slug, 'name' => $t->name,
                                    'parent' => (int) $t->parent);
          }
        }
        $u = get_user_by('login', 'oracle_author');
        if ($u) {
          $out['users'][] = array('id' => (int) $u->ID, 'login' => $u->user_login,
                                  'display_name' => $u->display_name);
        }
        foreach (array('hello-world','parent-page','child-page','grandchild-page','privacy-policy') as $slug) {
          $ps = get_posts(array('name' => $slug, 'post_type' => array('post','page'),
                                'post_status' => 'any', 'numberposts' => 1));
          if (!$ps) { continue; }
          $p = $ps[0];
          $out['posts'][] = array(
            'id' => (int) $p->ID, 'type' => $p->post_type, 'slug' => $p->post_name,
            'title' => $p->post_title, 'parent' => (int) $p->post_parent,
            'status' => $p->post_status, 'date' => $p->post_date_gmt,
            'template' => get_page_template_slug($p->ID),
            'comment_status' => $p->comment_status, 'comment_count' => (int) $p->comment_count
          );
        }
        echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
      PHP
    end

    # The theme's own documents, as `get_block_template()` builds them.
    def block_templates(rows)
      @block_templates ||= run(<<~PHP, JSON.generate(rows))
        $rows = json_decode(file_get_contents('php://stdin'), true);
        $out = array();
        foreach ($rows as $r) {
          $type = $r['kind'] === 'template' ? 'wp_template' : 'wp_template_part';
          $t = get_block_template(get_stylesheet() . '//' . $r['slug'], $type);
          $out[$r['kind'] . ':' . $r['slug']] = $t ? $t->content : null;
        }
        echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
      PHP
    end

    def run(body, stdin = "")
      file = Tempfile.new(["oracle", ".php"])
      file.write("<?php\nrequire_once '#{BOOTSTRAP}';\n#{body}")
      file.close
      out, err, status = Open3.capture3("php", file.path, stdin_data: stdin)
      raise "PHP oracle failed: #{err[0, 500]}" unless status.success?

      JSON.parse(out)
    ensure
      file&.unlink
    end
  end
end
