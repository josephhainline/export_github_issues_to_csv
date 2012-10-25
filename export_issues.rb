require 'octokit'
require 'csv'
require 'date'
require 'rubygems'
require 'highline/import'

TIMEZONE_OFFSET=ENV['GITHUB_TIMEZONE_OFFSET']
CSV_FILENAME=ENV['GITHUB_DEFAULT_CSV_FILENAME']
GITHUB_ORGANIZATION=ENV['GITHUB_ORGANIZATION_NAME']
GITHUB_USERNAME=ENV['GITHUB_USERNAME']
GITHUB_PASSWORD=ENV['GITHUB_PASSWORD']

TIMEZONE_OFFSET = "-5" if (TIMEZONE_OFFSET.nil?)

GITHUB_ORGANIZATION = ask("Enter Github organization name: ") if GITHUB_ORGANIZATION.nil?
puts "Getting ready to pull down all issues in the " + GITHUB_ORGANIZATION + " organization."

if (GITHUB_USERNAME.nil? || GITHUB_USERNAME.size < 1)
  username = ask("Enter Github username: ")
else
  puts "Github username: #{GITHUB_USERNAME}"
  username = GITHUB_USERNAME
end

if (GITHUB_PASSWORD.nil? || GITHUB_PASSWORD.size < 1)
  password = ask("Enter Github password: ") { |q| q.echo = false }
else
  password = GITHUB_PASSWORD
  puts "Github password: ***********"
end

if (CSV_FILENAME.nil? || CSV_FILENAME.size < 1)
  csv_file = ask("Enter output file path: ")
else
  csv_file = CSV_FILENAME
end


client = Octokit::Client.new(:login => username, :password => password)

csv = CSV.new(File.open(File.dirname(__FILE__) + csv_file, 'w'))

puts "Initialising CSV file " + csv_file + "..."
#CSV Headers
header = [
  "Repo",
  "Title",
  "Description",
  "Date created",
  "Date modified",
  "Issue type",
  "Milestone",
  "State",
  "Open/Closed",
  "Reporter",
  "URL"
]
# We need to add a column for each comment, so this dictates how many comments for each issue you want to support
#20.times { header << "Comments" }
csv << header

puts "Finding this organization's repositories..."
org_repos = client.organization_repositories(GITHUB_ORGANIZATION)
puts "\nFound " + org_repos.count.to_s + " repositories:"
org_repo_names = []
org_repos.each do |r|
  org_repo_names.push r['full_name']
  puts r['full_name']
end

all_issues = []

org_repo_names.each do |repo_name|
  puts "\nGathering issues in repo " + repo_name + "..."
  temp_issues = []
  issues = []
  page = 0
  begin
    page = page +1
    temp_issues = client.list_issues(repo_name, :state => "closed", :page => page)
    issues = issues + temp_issues
  rescue TypeError
    break
  end while not temp_issues.empty?
  temp_issues = []
  page = 0
  begin
    page = page +1
    temp_issues = client.list_issues(repo_name, :state => "open", :page => page)
    issues = issues + temp_issues
  rescue TypeError
    puts 'Issues are disabled for this repo.'
    break
  end while not temp_issues.empty?

  puts "Found " + issues.count.to_s + " issues."

  all_issues = all_issues + issues
end

puts "\n\n\n"
puts "-----------------------------"
puts "Found a total of #{all_issues.size} issues across #{org_repos.size} repositories."
puts "-----------------------------"

puts "Processing #{all_issues.size} issues..."
all_issues.each do |issue|

  puts "Processing issue #{issue['number']} at #{issue['html_url']}..."

  # Work out the type based on our existing labels
  case
    when issue['labels'].to_s =~ /Bug/i
      type = "Bug"
    when issue['labels'].to_s =~ /Feature/i
      type = "New feature"
    when issue['labels'].to_s =~ /Task/i
      type = "Task"
  end

  labelnames = []
  issue['labels'].each do |label|
    label.to_s =~ /name="(.+?)"/
    labelname = $1
    labelnames.push(labelname)
  end

  # Work out the state based on our existing labels
  state = ""
  labelnames.each do |n|
    case
      when n =~ /0 - /
        state = "0 - Backlog"
      when n =~ /1 - /
        state = "1 - Design Backlog"
      when n =~ /2 - /
        state = "2 - Design in Process"
      when n =~ /3 - /
        state = "3 - Ready for Coding"
      when n =~ /4 - /
        state = "4 - Coding in Process"
      when n =~ /5 - /
        state = "5 - Pull Request"
      when n =~ /6 - /
        state = "6 - Ready for QA"
      when n =~ /7 - /
        state = "7 - QA in Process"
      when n =~ /8 - /
        state = "8 - QA Approved"
      when n =~ /9 - /
        state = "9 - Ready for Demo"
    end
  end

  milestone = issue['milestone'] || "None"
  if (milestone != "None")
    milestone = milestone['title']
  end

  issue['html_url'] =~ /\/github.com\/(.+)\/issues\//
  repo_name = $1

  # Needs to match the header order above, date format are based on Jira default
  row = [
    repo_name,
    issue['title'],
    issue['body'],
    DateTime.parse(issue['created_at']).new_offset(TIMEZONE_OFFSET).strftime("%d/%b/%y %l:%M %p"),
    DateTime.parse(issue['updated_at']).new_offset(TIMEZONE_OFFSET).strftime("%d/%b/%y %l:%M %p"),
    type,
    milestone,
    state,
    issue['state'],
    issue['user']['login'],
    issue['html_url']
  ]
  csv << row
  end
