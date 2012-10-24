require 'octokit'
require 'csv'
require 'date'

# Description:
# Exports Github issues from one or more repos into CSV file formatted for import into JIRA
# Note: By default, all Github comments will be assigned to the JIRA admin, appended with
# a note indicating the Github user who added the comment (since you may not have JIRA users
# created for all your Github users, especially if it is a public/open-source project:
#
#  Administrator added a comment - 13/Jun/12 5:13 PM
#  Imported from Github issue xyz-123, originally reported by ubercoder42
#
#  Administrator added a comment - 12/Jun/12 10:00 AM
#  Github comment from ubercoder42: [Text from first comment here...]

# Usage:
# > ruby github_issues_to_csv_v3.rb <JIRA admin username> <Github username> <Github password> <Github project/user> <repo 1> .. <repo n>

# Your local timezone offset to convert times -- CHANGE THESE TO MATCH YOUR SETTINGS
TIMEZONE_OFFSET="-8"
COMMENT_DATE_FORMAT="%m/%d/%Y %T"

OTHER_DATE_FORMAT="%-m/%-d/%y %H:%M"  # Don't change this; Comments must be in this format
COMMENT_NOW = DateTime.now.new_offset(TIMEZONE_OFFSET).strftime(COMMENT_DATE_FORMAT)
# Grab command line args
JIRA_ADMIN=ARGV.shift
USERNAME=ARGV.shift
PASSWORD=ARGV.shift
USER=ARGV.shift


client = Octokit::Client.new(:login => USERNAME, :password => PASSWORD)

csv = CSV.new(File.open(File.dirname(__FILE__) + "/issues_#{USER}.csv", 'w'), :force_quotes=>true)

puts "Initialising CSV file..."
#CSV Headers
header = [
  "Summary",
  "Description",
  "Date created",
  "Date modified",
  "Issue type",
  "Milestone",
  "Priority",
  "Status",
  "Reporter",
  "Github repo",
  "Github number"
]
# We need to add a column for each comment, so this dictates how many comments for each issue you want to support
20.times { header << "Comments" }
csv << header

ARGV.each do |project|
	puts "Getting issues from #{project}..."
	temp_issues = []
	issues = []
	page = 0
	begin
		page = page +1
		temp_issues = client.list_issues("#{USER}/#{project}", :state => "closed", :page => page)
		issues = issues + temp_issues;
	end while not temp_issues.empty?
	temp_issues = []
	page = 0
	begin
		page = page +1
		temp_issues = client.list_issues("#{USER}/#{project}", :state => "open", :page => page)
		issues = issues + temp_issues;
	end while not temp_issues.empty?
	
	
	puts "Processing #{issues.size} issues..."
	issues.each do |issue|
	  puts "Processing issue #{project}-#{issue['number']}..."
	  # Work out the type based on our existing labels
	  case
		when issue['labels'].to_s =~ /Bug/i
		  type = "Bug"
		when issue['labels'].to_s =~ /Feature/i
		  type = "New feature"
		when issue['labels'].to_s =~ /Task/i
		  type = "Task"
	  end
	
	  # Work out the priority based on our existing labels
	  case
		when issue['labels'].to_s =~ /HIGH/i
		  priority = "Critical"
		when issue['labels'].to_s =~ /MEDIUM/i
		  priority = "Major"
		when issue['labels'].to_s =~ /LOW/i
		  priority = "Minor"
	  end
	  milestone = issue['milestone'] || "None"
	  if (milestone != "None")
		milestone = milestone['title']
	  end
	
	  # Needs to match the header order above
	  row = [
		issue['title'],
		issue['body'],
		DateTime.parse(issue['created_at']).new_offset(TIMEZONE_OFFSET).strftime(OTHER_DATE_FORMAT),
		DateTime.parse(issue['updated_at']).new_offset(TIMEZONE_OFFSET).strftime(OTHER_DATE_FORMAT),
		type,
		milestone,
		priority,
		issue['state'],
		issue['user']['login'],
		project,
		"#{project}-#{issue['number']}"
	  ]
	  row << "#{COMMENT_NOW}; #{JIRA_ADMIN}; Imported from Github issue #{project}-#{issue['number']}, originally reported by #{issue['user']['login']}"
	  if issue['comments'] > 0
		puts "Getting #{issue['comments']} comments for issue #{project}-#{issue['number']} from Github..."
		# Get the comments
		comments = client.issue_comments("#{USER}/#{project}", issue['number'])
	
		comments.each do |c|
		  # Date format needs to match hard coded format in the Jira importer
		  comment_time = DateTime.parse(c['created_at']).new_offset(TIMEZONE_OFFSET).strftime(COMMENT_DATE_FORMAT)
	
		  # Map usernames for the comments importer. As is, this will assign all comments to
		  # JIRA admin user -- use the commented version if you want to use the Github username...
		  comment_user = JIRA_ADMIN  # c['user']['login']
	
		  # Put the comment in a format Jira can parse
		  comment = "#{comment_time}; #{comment_user}; Github comment from #{c['user']['login']}: #{c['body']}"
	
		  row << comment
		end
	  end
	  csv << row
  end
end